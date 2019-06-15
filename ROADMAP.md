Introduction
------------

This started as a quick hack some years ago, when I broke my PostgreSQL database 
(must have been version 7.3 or so) so that pg_dump wouldn't dump it anymore.
Plus it couldn't handle dumping say only functions from certain schema. 
I have since then learned how to fix my database and pg_dump got options like --schema.

But the idea of a database being able to dump itself more autonomously persisted.
After all, if LISP can do it, why not Postgres with its awesome SQL power? 
Information is all there in the system catalogs. One just needs to decipher it.

This tool uses information schema and standard SQL as much as possible, 
but for any actual practical use decoding of PostgreSQL system catalogs is required. 
Querying pg_catalog can turn out to be quite complicated for a somewhat casual SQL user.
This project attempts to collect many SQL snippets made over the years into a coherent extension.

This will hopefully help to keep relevant SQL code for these things in one place.

Tasks
-----

Support for other postgres objects:
- access method, operator family, operator class, pg_amop, pg_amproc
- extension
- policy
- PG 10: publication, subscription
- PG 10: statistics
- PG 11: procedures

Support for other missing options:
- column options
- row level permissions
- PG 10: partitions
- comments on all objects
- ownership of all objects 
- grants on all objects (missing: fdw, server)
- serial (alter sequence set owner column)
- grants vs superuser (grantor)
- database settings (alter database set)
- PG 10+: generated
- fillfactor
- pre/post data

Other:
- PG version specific tests
- use ONLY when appropriate
- improve support for non superusers (more testing, etc)
- improve dumping of comments (be quiet on NULL comments)
- handle dependancies for types better (use shell types)
- handle SERIAL sequences better
- improve and add to simple tests
- make some tests to test if what we output actually runs, test execute them
- make some tests which compare to output of pg_dump for any sql file:
  test load file -> pg_dump compared to load file -> ddl_dump -> reload -> pg_dump

Options
-------

Some options as to what and how to dump stuff might be required:

    CREATE TYPE pg_ddl_options AS (
      ddldrop  boolean, -- generate DROP statements
      ddlalter boolean, -- prefer ALTER to CREATE
      ddldcl   boolean, -- include DCL (GRANTS)
      ddlcor   boolean, -- CREATE OR REPLACE 
      ddline   boolean, -- IF NOT EXISTS
      ddlie    boolean, -- IF EXISTS
      ddlwrap  boolean, -- wrap in BEGIN / END
      ddldep   boolean, -- output objects which depend on this object too
      ddldata  boolean  -- add statements preserve / copy table data
    );

These might be passed as optional second arg to extractor functions
Perhaps as a text array? JSON?

Perhaps there are other ways to implement some of this?

Other DDL dumping tools
-----------------------

### psql

Command line client `psql` contains lots of packaged SQL for handling metadata 
mainly to support code completion and various \d* commands.

### pg_dump

Database dump tool `pg_dump` contains lots of packaged SQL for handling metadata 
and especially considers various dependancies. Source code for main C is is about 20000 
lines long.

### pgAdmin3

PgAdmin3 DDL generation and schema handling code is an interesting 
mix of wxWidgets GUI toolkit (C++) and SQL. It requires GUI.
Generated DDLs are database administrator friendly.



