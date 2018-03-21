Intro
-----

This started as a quick hack some years ago, when I broke my PostgreSQL database 
(must have been version 7.3 or so) so that pg_dump wouldn't dump it anymore.
Plus it couldn't handle dumping say only functions from certain schema. 
I have since then learned how to fix my database and pg_dump got options like --schema.

But the idea of a database being able to dump itself more autonomously persisted.
After all, if LISP can do it, why not Postgres with its' awesome SQL power? 
Information is all there in the system catalogs, one just needs to decypher it.

This tool uses information schema and standard SQL as much as possible, 
but for any actual practical use decoding of PostgreSQL system catalogs is required. 
Querying pg_catalog can turn out to be quite complicated for a somewhat casual SQL user.

This will hopefully help to keep relevant SQL code for these thing in one place.

Tasks
-----

Support for other postgres objects:
- regnamespace
- regconfig, regdictionary
- event triggers
- operator class
- text search parser, template
- fdw, server, user mapping
- transform, cast, rule, collation
- extension, language
- access method, conversion, tablespace
- database, policy
- v10: publication, subscription, statistics

Support for other missing options:
- storage parameters
- tablespaces
- serial (alter sequence set owner column)
- column grants
- schema grants
- comments everywhere
- v10: partitions

- compiler from one source to specific pg version

- improve and add to simple tests
- make some tests to test if what we output actually runs, test execute them
- make some tests which compare to output of pg_dump for any sql file:
  test load file -> pg_dump compared to load file -> ddl_dump -> reload -> pg_dump
- dump also comments on constraints, indexes, triggers, etc...

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

### pgdump

Database dump tool `pgdump` contains lots of packaged SQL for handling metadata 
and especially consideres various dependancies.

### pgAdmin3

PgAdmin3 DDL generation and schema handling code is an interesting 
mix of wxWidgets GUI toolkit (C++) and SQL. It requires GUI.
Generated DDLs are database administrator friendly.



