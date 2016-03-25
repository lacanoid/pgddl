DDL extractor functions  for PostgreSQL
=======================================

This is an SQL-only extension for PostgreSQL that provides functions for generating 
SQL DDL scripts for objects stored in a database.

Advantages over using other tools like `psql` or `pgdump` include:

- You can use it with any client which support running plain SQL queries
- No shell commands with hairy options required (for running pg_dump), just use SELECT
- With SQL you can dump things like say only functions with matching name from all schemas
- Created scripts are somewhat more intended to be run manually in a client

Some other SQL databases support commands like SHOW CREATE TABLE or provide callable 
functions for the purpose. 

It is currently woefully incomplete, but still useful. Tested on PostgreSQL 9.4.


Plans on how to make this support newer fetures AND older servers are being considered.
 

Installation
------------

To build and install this module:

    make
    make install

or selecting a specific PostgreSQL installation:

    make PG_CONFIG=/some/where/bin/pg_config
    make PG_CONFIG=/some/where/bin/pg_config install

And finally inside the database:

    CREATE EXTENSION ddl;

Using
-----

This module provides one main end user function `pg_ddl_script` that 
you can use to obtain SQL DDL source for a particular database object.

Currently supported object types are `regclass`,`regproc` and `regprocedure`.
You will need to cast object name or oid to appropriate type.

- `pg_ddl_script(regclass) returns text`

    Extracts SQL DDL source of a class (table or view) `regclass`.

- `pg_ddl_script(regproc) returns text`
- `pg_ddl_script(regprocedure) returns text`

    Extracts SQL DDL source of a function.

For example:

```sql
CREATE TABLE users (
    id int PRIMARY KEY,
    name text
);

SELECT pg_ddl_script('users'::regclass);
```

A number of other functions are provided to extract more specific objects:

- `pg_ddl_create_table(regclass) returns text`

    Extracts SQL DDL source of a table.

- `pg_ddl_create_view(regclass) returns text`

    Extracts SQL DDL source of a view.

- `pg_ddl_create_class(regclass) returns text`

    Extracts SQL DDL source of a table or view.

- `pg_ddl_create_function(regprocedure) returns text`

    Extracts SQL DDL source of a function.


