This tools uses information schema and standard SQL as much as possible, but for any actual use decoding of
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

