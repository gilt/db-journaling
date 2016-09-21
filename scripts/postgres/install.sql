create or replace function journal.refresh_journal_trigger(
  p_source_schema_name in varchar,
  p_source_table_name in varchar,
  p_target_schema_name in varchar = 'journal',
  p_target_table_name in varchar = null
) returns varchar language plpgsql as $$
declare
  v_insert_trigger_name text;
  v_delete_trigger_name text;
begin
  v_insert_trigger_name := journal.refresh_journal_insert_trigger(p_source_schema_name, p_source_table_name, p_target_schema_name, coalesce(p_target_table_name, p_source_table_name));
  v_delete_trigger_name := journal.refresh_journal_delete_trigger(p_source_schema_name, p_source_table_name, p_target_schema_name, coalesce(p_target_table_name, p_source_table_name));

  return v_insert_trigger_name || ' ' || v_delete_trigger_name;
end;
$$;

create or replace function journal.refresh_journal_delete_trigger(
  p_source_schema_name in varchar, p_source_table_name in varchar,
  p_target_schema_name in varchar, p_target_table_name in varchar
) returns varchar language plpgsql as $$
declare
  row record;
  v_journal_name text;
  v_source_name text;
  v_trigger_name text;
  v_sql text;
  v_target_sql text;
begin
  v_journal_name = p_target_schema_name || '.' || p_target_table_name;
  v_source_name = p_source_schema_name || '.' || p_source_table_name;
  v_trigger_name = p_target_table_name || '_journal_delete_trigger';
  -- create the function
  v_sql = 'create or replace function ' || v_journal_name || '_delete() returns trigger language plpgsql as ''';
  v_sql := v_sql || ' begin ';
  v_sql := v_sql || '  insert into ' || v_journal_name || ' (journal_operation';
  v_target_sql = 'TG_OP';

  for row in (select column_name from information_schema.columns where table_schema = p_source_schema_name and table_name = p_source_table_name order by ordinal_position) loop
    v_sql := v_sql || ', ' || row.column_name;
    v_target_sql := v_target_sql || ', old.' || row.column_name;
  end loop;

  v_sql := v_sql || ') values (' || v_target_sql || '); ';
  v_sql := v_sql || ' return null; end; ''';

  execute v_sql;

  -- create the trigger
  v_sql = 'drop trigger if exists ' || v_trigger_name || ' on ' || v_source_name || '; ' ||
          'create trigger ' || v_trigger_name || ' after delete on ' || v_source_name ||
          ' for each row execute procedure ' || v_journal_name || '_delete()';

  execute v_sql;

  return v_trigger_name;

end;
$$;

create or replace function journal.refresh_journal_insert_trigger(
  p_source_schema_name in varchar, p_source_table_name in varchar,
  p_target_schema_name in varchar, p_target_table_name in varchar
) returns varchar language plpgsql as $$
declare
  row record;
  v_journal_name text;
  v_source_name text;
  v_trigger_name text;
  v_first boolean;
  v_sql text;
  v_target_sql text;
  v_name text;
begin
  v_journal_name = p_target_schema_name || '.' || p_target_table_name;
  v_source_name = p_source_schema_name || '.' || p_source_table_name;
  v_trigger_name = p_target_table_name || '_journal_insert_trigger';
  -- create the function
  v_sql = 'create or replace function ' || v_journal_name || '_insert() returns trigger language plpgsql as ''';
  v_sql := v_sql || ' begin ';

  for v_name in (select * from journal.primary_key_columns(p_source_schema_name, p_source_table_name)) loop
    v_sql := v_sql || '  if (TG_OP=''''UPDATE'''' and (old.' || v_name || ' != new.' || v_name || ')) then';
    v_sql := v_sql || '    raise exception ''''Table[' || v_source_name || '] is journaled. Updates to primary key column[' || v_name || '] are not supported as this would make it impossible to follow the history of this row in the journal table[' || v_journal_name || ']'''';';
    v_sql := v_sql || '  end if;';
  end loop;

  v_sql := v_sql || '  insert into ' || v_journal_name || ' (journal_operation';
  v_target_sql = 'TG_OP';

  for row in (select column_name from information_schema.columns where table_schema = p_source_schema_name and table_name = p_source_table_name order by ordinal_position) loop
    v_sql := v_sql || ', ' || row.column_name;
    v_target_sql := v_target_sql || ', new.' || row.column_name;
  end loop;

  v_sql := v_sql || ') values (' || v_target_sql || '); ';
  v_sql := v_sql || ' return null; end; ''';

  execute v_sql;

  -- create the trigger
  v_sql = 'drop trigger if exists ' || v_trigger_name || ' on ' || v_source_name || '; ' ||
          'create trigger ' || v_trigger_name || ' after insert or update on ' || v_source_name ||
          ' for each row execute procedure ' || v_journal_name || '_insert()';

  execute v_sql;

  return v_trigger_name;

end;
$$;

create or replace function journal.get_data_type_string(
  p_column information_schema.columns
) returns varchar language plpgsql as $$
declare
  journal_data_type   text;
begin
  IF p_column.data_type = 'numeric' THEN
    IF p_column.numeric_precision IS NOT NULL AND p_column.numeric_scale IS NOT NULL THEN
      journal_data_type := p_column.data_type || '(' || p_column.numeric_precision::varchar || ',' || p_column.numeric_scale::varchar || ')';
    ELSE
      journal_data_type := p_column.data_type;
    END IF;
  ELSEIF p_column.data_type IN ('character', 'character varying', '"char"') THEN
    journal_data_type := 'text';
  ELSE
    journal_data_type := p_column.data_type;
  END IF;

  return journal_data_type;
end;
$$;

create or replace function journal.primary_key_columns(
  p_schema_name in varchar,
  p_table_name in varchar
) returns setof text language plpgsql AS $$
declare
  row record;
begin
  for row in (
      select key_column_usage.column_name
        from information_schema.table_constraints
        join information_schema.key_column_usage
             on key_column_usage.table_name = table_constraints.table_name
            and key_column_usage.table_schema = table_constraints.table_schema
            and key_column_usage.constraint_name = table_constraints.constraint_name
       where table_constraints.constraint_type = 'PRIMARY KEY'
         and table_constraints.table_schema = p_schema_name
         and table_constraints.table_name = p_table_name
       order by coalesce(key_column_usage.position_in_unique_constraint, 0),
                coalesce(key_column_usage.ordinal_position, 0),
                key_column_usage.column_name
  ) loop
    return next row.column_name;
  end loop;
end;
$$;


create or replace function journal.add_primary_key_data(
  p_source_schema_name in varchar, p_source_table_name in varchar,
  p_target_schema_name in varchar, p_target_table_name in varchar
) returns void language plpgsql as $$
declare
  v_name text;
  v_columns character varying := '';
begin
  for v_name in (select * from journal.primary_key_columns(p_source_schema_name, p_source_table_name)) loop
    if v_columns != '' then
      v_columns := v_columns || ', ';
    end if;
    v_columns := v_columns || v_name;
    execute 'alter table ' || p_target_schema_name || '.' || p_target_table_name || ' alter column ' || v_name || ' set not null';
  end loop;

  if v_columns != '' then
    execute 'create index on ' || p_target_schema_name || '.' || p_target_table_name || '(' || v_columns || ')';
  end if;

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
      -- There are no constraints (other than not null on primary key columns) on the journaling table
      -- columns anyway, so leaving it populated with null will be fine.
      select journal.get_data_type_string(information_schema.columns.*) into v_data_type from information_schema.columns where table_schema = p_target_schema_name and table_name = p_target_table_name and column_name = row.column_name;
      if not found then
        execute 'alter table ' || v_journal_name || ' add ' || row.column_name || ' ' || row.data_type;
      elsif (row.data_type != v_data_type) then
        execute 'alter table ' || v_journal_name || ' alter column ' || row.column_name || ' type ' || row.data_type;
      end if;

    end loop;
  else
    execute 'create table ' || v_journal_name || ' as select * from ' || p_source_schema_name || '.' || p_source_table_name || ' limit 0';
    execute 'alter table ' || v_journal_name || ' add journal_timestamp timestamp with time zone not null default now() ';
    execute 'alter table ' || v_journal_name || ' add journal_operation text not null ';
    execute 'alter table ' || v_journal_name || ' add journal_id bigserial primary key ';
    execute 'comment on table ' || v_journal_name || ' is ''Created by plsql function refresh_journaling to shadow all inserts and updates on the table ' || p_source_schema_name || '.' || p_source_table_name || '''';
    perform journal.add_primary_key_data(p_source_schema_name, p_source_table_name, p_target_schema_name, p_target_table_name);
  end if;

  perform journal.refresh_journal_trigger(p_source_schema_name, p_source_table_name, p_target_schema_name, p_target_table_name);

  return v_journal_name;

end;
$$;

--note: creating event_triggers requires superuser privileges
create or replace function journal.create_event_trigger(
  p_source_schema_name in varchar, p_source_table_name in varchar,
  p_target_schema_name in varchar, p_target_table_name in varchar
) returns void language plpgsql as $$
declare
  v_journal_name text;
  v_source_name text;
  v_function_sql text;
  v_trigger_sql text;
begin
  v_journal_name = p_target_schema_name || '.' || p_target_table_name;
  v_source_name = p_source_schema_name || '.' || p_source_table_name;
  if exists(select 1 from information_schema.tables where table_schema = p_target_schema_name and table_name = p_target_table_name) then
    v_function_sql =                    'CREATE OR REPLACE FUNCTION refresh_' || p_source_table_name || '_journal() RETURNS event_trigger AS ''';
    v_function_sql := v_function_sql || ' declare ';
    v_function_sql := v_function_sql || ' r RECORD; ';
    v_function_sql := v_function_sql || ' func_exists boolean; ';
    v_function_sql := v_function_sql || 'BEGIN ';
    --for postgres 9.4 compatability, so we don't throw errors
    v_function_sql := v_function_sql || 'select exists(select * from pg_proc where proname = ''pg_event_trigger_ddl_commands'') into func_exists; ';
    v_function_sql := v_function_sql || 'IF func_exists THEN ';
    v_function_sql := v_function_sql || '  FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP ';
    v_function_sql := v_function_sql || '    IF r.object_identity = ''' || v_source_name || ''' THEN ';
    v_function_sql := v_function_sql || '      perform journal.refresh_journaling(''' || p_source_schema_name || ''', ''' || p_source_table_name || ''', ''' || p_target_schema_name || ''', ''' || p_target_table_name ||'''); ';
    v_function_sql := v_function_sql || '    END IF; ';
    v_function_sql := v_function_sql || '  END LOOP; ';
    v_function_sql := v_function_sql || 'END IF; ';
    v_function_sql := v_function_sql || 'END; ';
    v_function_sql := v_function_sql || '''';
    v_function_sql := v_function_sql || 'LANGUAGE plpgsql;';

    v_trigger_sql =                   'CREATE EVENT TRIGGER tr_refresh_' || p_source_table_name || 'journal ';
    v_trigger_sql := v_trigger_sql || 'ON ddl_command_end WHEN TAG IN (''ALTER TABLE'') ';
    v_trigger_sql := v_trigger_sql || 'EXECUTE PROCEDURE refresh_' || p_source_table_name || '_journal(); ';

    perform v_function_sql;
    perform v_trigger_sql;

  else
		raise exception 'Unable to create journal event trigger for table without journaling. Use journal.create_journaling instead';
  end if;
end;
$$;


--note this requires superuser privileges
create or replace function journal.create_journaling(
  p_source_schema_name in varchar, p_source_table_name in varchar,
  p_target_schema_name in varchar, p_target_table_name in varchar
) returns varchar language plpgsql as $$
declare
  v_journal_name varchar;
begin
	select journal.refresh_journaling(p_source_schema_name, p_source_table_name, p_target_schema_name, p_target_table_name) into v_journal_name;
  perform journal.create_event_trigger(p_source_schema_name, p_source_table_name, p_target_schema_name, p_target_table_name);
	return v_journal_name;
end;
$$;

