Intro
-----

This started as a quick hack some years ago, when I broke my database so pg_dump wouldn't dump it anymore.
Plus it couldn't handle dumping say only functions from certain schema. 
I have since then learned how to fix my database and pg_dump got options like -n.

But the idea of a database being able to dump itself more autonomously persisted.

This tool uses information schema and standard SQL as much as possible, but for any actual use decoding of
PostgreSQL system catalogs is required. 

Querying pg_catalog can turn out to be quite complicated for a somewhat casual SQL user.


Other tools
-----------

### psql

Command line client `psql` contains lots of packaged SQL for handling metadata 
mainly to support code completion and various \d* commands.

### pgdump

Database dump tool `pgdump` contains lots of packaged SQL for handling metadata 
mainly to support code completion and various \d* commands.

### pgAdmin3

PgAdmin3 DDL generation and schema handling code is an interesting 
mix of wxWidgets GUI toolkit (C++) and SQL.


This will hopefully help to keep SQL code in one place.

