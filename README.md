db-journaling
=============

A set of scripts to add automatic journaling to your database
objects. Once installed for a given table, all insert or update will
be copied into an append only table in a schema that you specify.


Installation
-------------
psql -f scripts/postgres/install.sql databasename


Example
-------------
See example file for an end to end example.


To install / update
-------------

Ruby is required to use the command-line tools.

### Postgres

./install/postgres-journaling --help

This script requires that you have psql installed (and on your PATH) from the location where you run it.


Database Implementations
-------------

### Postgres

This installs a trigger that copies the current record into a separate journaling schema upon INSERT or UPDATE. As such, it is simple but verbose - be careful adding journaling to large tables with many updates. Example usage:

```sql
create table foo (id bigserial, key text not null);
select journal.refresh_journaling('public', 'foo', 'journal', 'foo');
```

Calling the refresh_journaling function will create this table and replicate all changes from foo to journal.foo:

```sql
> \d journal.foo
                                  Table "journal.foo"
   Column   |  Type  |                            Modifiers
------------+--------+------------------------------------------------------------------
 id         | bigint |
 key        | text   |
 journal_id | bigint | not null default nextval('journal.foo_journal_id_seq'::regclass)
Indexes:
    "foo_pkey" PRIMARY KEY, btree (journal_id)
    "foo_id_idx" btree (id)
```
