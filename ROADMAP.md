Intro
-----

This started as a quick hack some years ago, when I broke my PostgreSQL database 
(must have been version 7.3 or so) so that pg_dump wouldn't dump it anymore.
Plus it couldn't handle dumping say only functions from certain schema. 
I have since then learned how to fix my database and pg_dump got options like -n.

But the idea of a database being able to dump itself more autonomously persisted.
After all, if LISP can do it, why not Postgres with it's awesome SQL power? 
Information is all there in the system catalogs, one just needs to decypher it.

This tool uses information schema and standard SQL as much as possible, 
but for any actual practical use decoding of PostgreSQL system catalogs is required. 
Querying pg_catalog can turn out to be quite complicated for a somewhat casual SQL user.

This will hopefully help to keep SQL code in one place.

Options
-------

CREATE TYPE pg_ddl_options AS (
  ddldrop  boolean, -- generate DROP statements
  ddlalter boolean, -- prefer ALTER to CREATE
  ddlcor   boolean, -- CREATE OR REPLACE 
  ddline   boolean, -- IF NOT EXISTS
  ddlwrap  boolean, -- wrap in BEGIN / END
  ddldep   boolean, -- output objects which depend on this object too
  ddldata  boolean  -- add statements preserve / copy table data
);

Tasks
-----

- support for regtypes
-- enums
-- domains
-- composites (dump as tables and views when appropriate)

- support for sequences

- support for other missing stuff:
-- storage parameters
-- tablespaces

- improve simple tests
- make some tests to test if what we make actually runs
- make some tests which compare to output of pg_dump for any sql file:
  test load file -> pg_dump compared to load file -> ddl_dump -> reload -> pg_dump
- dump also comments on constraints, indexes, triggers, etc...
- find out the minimum version of Postgres this works on

- support for dumping whole schemas
- recursive dumper which handles dependancies
- support for foreign tables
- support for roles
- support for other postgres objects


Other tools
-----------

### psql

Command line client `psql` contains lots of packaged SQL for handling metadata 
mainly to support code completion and various \d* commands.

### pgdump

Database dump tool `pgdump` contains lots of packaged SQL for handling metadata 
and especially consideres various dependancies.

### pgAdmin3

PgAdmin3 DDL generation and schema handling code is an interesting 
mix of wxWidgets GUI toolkit (C++) and SQL. It requires GUI.
Generated DDLs are database administrator friendly.



