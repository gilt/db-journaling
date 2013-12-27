create or replace function journal.refresh_journal_trigger(
  p_source_schema_name in varchar, p_source_table_name in varchar,
  p_target_schema_name in varchar, p_target_table_name in varchar
) returns varchar language plpgsql as $$
declare
  row record;
  v_journal_name text;
  v_trigger_name text;
  v_first boolean;
  v_sql text;
begin
  v_journal_name = p_target_schema_name || '.' || p_target_table_name;
  v_trigger_name = p_target_table_name || '_journal_insert_trigger';
  -- create the function
  v_sql = 'create or replace function ' || v_journal_name || '_insert() returns trigger language plpgsql as ''';
  v_sql := v_sql || ' begin ';
  v_sql := v_sql || '  insert into ' || v_journal_name || ' (';

  v_first = true;
  for row in (select column_name from information_schema.columns where table_schema = p_source_schema_name and table_name = p_source_table_name order by ordinal_position) loop

    if (v_first) then
      v_first := false;
    else
      v_sql := v_sql || ', ';
    end if;
    v_sql := v_sql || row.column_name;

  end loop;

  v_sql := v_sql || ') values (new.*); ';
  v_sql := v_sql || ' return null; end; ''';

  execute v_sql;

  -- create the trigger
  v_sql = 'drop trigger if exists ' || v_trigger_name || ' on ' || p_source_table_name || '; ' ||
          'create trigger ' || v_trigger_name || ' after insert or update on ' ||
          p_source_schema_name || '.' || p_source_table_name ||
          ' for each row execute procedure ' || v_journal_name || '_insert()';

  execute v_sql;

  return v_trigger_name;

end;
$$;

create or replace function journal.get_data_type_string(
  p_column information_schema.columns
) returns varchar language plpgsql as $$
begin
  return case p_column.data_type
    when 'numeric' then p_column.data_type || '(' || p_column.numeric_precision_radix::varchar || ',' || p_column.numeric_scale::varchar || ')'
    when 'character' then p_column.data_type || '(' || p_column.character_maximum_length::varchar || ')'
    else p_column.data_type
    end;
end;
$$;

create or replace function journal.refresh_journaling(
  p_source_schema_name in varchar, p_source_table_name in varchar,
  p_target_schema_name in varchar, p_target_table_name in varchar
) returns varchar language plpgsql as $$
declare
  row record;
  v_journal_name text;
  v_data_type character varying;
begin
  v_journal_name = p_target_schema_name || '.' || p_target_table_name;
  if exists(select 1 from information_schema.tables where table_schema = p_target_schema_name and table_name = p_target_table_name) then
    for row in (select column_name, journal.get_data_type_string(information_schema.columns.*) as data_type from information_schema.columns where table_schema = p_source_schema_name and table_name = p_source_table_name order by ordinal_position) loop

      -- NB: Specifically choosing to not drop deleted columns from the journal table, to preserve the data.
      -- There are no constraints on the journaling table columns anyway, so leaving it populated with null will be fine.
      select journal.get_data_type_string(information_schema.columns.*) into v_data_type from information_schema.columns where table_schema = p_target_schema_name and table_name = p_target_table_name and column_name = row.column_name;
      if not found then
        execute 'alter table ' || v_journal_name || ' add ' || row.column_name || ' ' || row.data_type;
      elsif (row.data_type != v_data_type) then
        execute 'alter table ' || v_journal_name || ' alter column ' || row.column_name || ' type ' || row.data_type;
      end if;

    end loop;
  else
    execute 'create table ' || v_journal_name || ' as select * from ' || p_source_schema_name || '.' || p_source_table_name || ' limit 0';
    execute 'alter table ' || v_journal_name || ' add journal_id bigserial primary key ';
    execute 'comment on table ' || v_journal_name || ' is ''Created by plsql function refresh_journaling to shadow all inserts and updates on the table ' || p_source_schema_name || '.' || p_source_table_name || '''';
    execute 'create index ' || p_target_table_name || '_id_idx on ' || v_journal_name || '(id)';

  end if;

  perform journal.refresh_journal_trigger(p_source_schema_name, p_source_table_name, p_target_schema_name, p_target_table_name);

  return v_journal_name;

end;
$$;