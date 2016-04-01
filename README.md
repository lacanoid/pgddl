DDL extractor functions  for PostgreSQL
=======================================

This is an SQL-only extension for PostgreSQL that provides functions for generating 
SQL DDL scripts for objects stored in a database.

Some other SQL databases support commands like SHOW CREATE TABLE or provide callable 
functions for the purpose. 

PostgreSQL currently does not provide overall in-server DDL extracting functions,
but rather just separate `pg_dump` program, which is an external tool to the server 
and therefore usually requires shell access or local installation to use.

PostgreSQL does however provide a number of helper functions which greatly help with
reconstructing DDL and are of course used by this extension.

Advantages over using other tools like `psql` or `pgdump` include:

- You can use it extract DDL with any client which support running plain SQL queries
- With SQL you can dump things like say only functions with matching names from chosen schemas
- Created scripts are somewhat more intended to be run and copy/pasted manually by the DBA
- No shell commands with hairy options required (for running pg_dump), just use SELECT

It is currently rather incomplete, but still useful. 
It provides support for most basic objects. 
Tested on PostgreSQL 9.4.

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

It you use multiple schemas, you will need to have variable `search_path` 
set appropriately for the extension to work. To make it work with any value of
`search_path`, you can install the extension in the `pg_catalog` schema:

    CREATE EXTENSION ddl SCHEMA pg_catalog;

This of course requires superuser privileges.

Using
-----

This module provides one main end user function `pg_ddl_script` that 
you can use to obtain SQL DDL source for a particular database object.

Currently supported object types are `regclass`,`regproc` and `regprocedure`.
You will probably want to cast object name or oid to appropriate type.

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

A number of other functions are provided to extract more specific objects.
They are used internally by the extension and are possibly subject to change in 
future versions of the extension. They are generraly not intended to be used
by the end user. 
They are:

- `pg_ddl_create_table(regclass) returns text`

    Extracts SQL DDL source of a table.

- `pg_ddl_create_view(regclass) returns text`

    Extracts SQL DDL source of a view.

- `pg_ddl_create_class(regclass) returns text`

    Extracts SQL DDL source of a table or view.

- `pg_ddl_create_function(regprocedure) returns text`

    Extracts SQL DDL source of a function.


