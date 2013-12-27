db-journaling
=============

A set of scripts to add automatic journaling to your database objects


To install / update
-------------

Ruby is required to use the command-line tools.

### Postrges

./install/postrges.rb --help

This script requires that you have psql installed (and on your PATH) from the location where you run it.


Database Implementations
-------------

### Postgres

This installs a trigger that copies the current record into a separate journaling schema upon INSERT or UPDATE. As such, it is simple but verbose - be careful adding journaling to large tables with many updates. Example usage:

```sql
create table foo (id bigserial, key text not null);
select journal_util.refresh_journaling('public', 'foo', 'journal', 'foo');
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