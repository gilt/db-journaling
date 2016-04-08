create or replace function journal.get_deleted_by_user_id() returns varchar language plpgsql as $$
declare
  v_result varchar;
begin
  -- will throw exception if not set:
  -- 'unrecognized configuration parameter "journal.deleted_by_user_id"
  select current_setting('journal.deleted_by_user_id') into v_result;
  return v_result;
exception when others then
  -- throw a better error message
  RAISE EXCEPTION 'journal.deleted_by_user_id is not set, Please use util.delete_by_id';
end;
$$;

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

    if row.column_name = 'updated_by_user_id' then
      v_target_sql := v_target_sql || ', journal.get_deleted_by_user_id()';
    else
      v_target_sql := v_target_sql || ', old.' || row.column_name;
    end if;
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
begin
  return case p_column.data_type
    when 'numeric' then p_column.data_type || '(' || p_column.numeric_precision_radix::varchar || ',' || p_column.numeric_scale::varchar || ')'
    when 'character' then 'text'
    when 'character varying' then 'text'
    when '"char"' then 'text'
    else p_column.data_type
    end;
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
    perform journal.create_prevent_update_trigger(p_target_schema_name, p_target_table_name);
    perform journal.create_prevent_delete_trigger(p_target_schema_name, p_target_table_name);
  end if;

  perform journal.refresh_journal_trigger(p_source_schema_name, p_source_table_name, p_target_schema_name, p_target_table_name);

  return v_journal_name;

end;
$$;

create or replace function journal.create_prevent_delete_trigger(p_schema_name character varying, p_table_name character varying) returns character varying
  language plpgsql
  as $$
declare
  v_name varchar;
begin
  v_name = p_table_name || '_prevent_delete_trigger';
  execute 'create trigger ' || v_name || ' before delete on ' || p_schema_name || '.' || p_table_name || ' for each row execute procedure journal.prevent_delete()';
  return v_name;
end;
$$;

create or replace function journal.prevent_delete() returns trigger
  language plpgsql
  as $$
begin
  raise exception 'Physical deletes are not allowed on this table';
end;
$$;

create or replace function journal.create_prevent_update_trigger(p_schema_name character varying, p_table_name character varying) returns character varying
  language plpgsql
  as $$
declare
  v_name varchar;
begin
  v_name = p_table_name || '_prevent_update_trigger';
  execute 'create trigger ' || v_name || ' before update on ' || p_schema_name || '.' || p_table_name || ' for each row execute procedure journal.prevent_update()';
  return v_name;
end;
$$;

create or replace function journal.prevent_update() returns trigger
  language plpgsql
  as $$
begin
  raise exception 'Physical updates are not allowed on this table';
end;
$$;
