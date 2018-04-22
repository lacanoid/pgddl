DDL extractor functions  for PostgreSQL
=======================================

This is an SQL-only extension for PostgreSQL that provides uniform functions for generating 
SQL Data Definition Language (DDL) scripts for objects stored in a database. 
It contains a bunch of SQL functions  to convert PostgreSQL system catalogs 
to nicely formatted snippets of SQL DDL, such as CREATE TABLE.

Some other SQL databases support commands like SHOW CREATE TABLE or provide 
other facilities for the purpose. 

PostgreSQL currently doesn't provide overall in-server DDL extracting functions,
but rather just a separate `pg_dump` program. It is an external tool to the server 
and therefore requires shell access or local installation to be of use.

PostgreSQL however already provides a number of helper functions which already greatly help 
with reconstructing DDL and are of course used by this extension.
It also has sophisticated query capabilities which make this project possible.

Advantages over using other tools like `psql` or `pgdump` include:

- You can use it to extract DDL with **any client** which support running plain SQL queries
- With SQL you can select things to dump by using usual SQL semantics (WHERE, etc)
- Special function for creating scripts, which drop and recreate entire **dependancy trees**.
  This is useful for example, when one wishes to rename some columns in a view with dependants.
  This works particularly great with transactional DDL of Postgres.
- Created scripts are somewhat more intended to be run and copy/pasted manually by the DBA
  into other databases/scripts. This involves 
   pretty printing,
   using **idempotent DDL** where possible (preferring ALTER to CREATE), 
   creating indexes which are part of a constraint with ADD CONSTRAINT and so on.
- **No shell access** or shell commands with hairy options required (for running pg_dump), just use SELECT and hairy SQL!
- It is entrely made out of **plain SQL functions**. It is also a kind of a reference for system catalogs.

Some disadvantages:

- Not all Postgres objects and all options are supported yet. 
  The package provides support for basic user-level objects such as types, classes and functions.
  Initially, support for all `reg*` objects and SQL standard compliant stuff is planned first,
  with more fringe stuff coming later. See [ROADMAP](ROADMAP.md)
- It is not well tested at all. While it contains a number of regression tests, these can be
  hardly considered as proofs of correctness. Be certain there are bugs. Use at your own risk!
  Do not run generated scripts on production databases without testing them!
- It is kind of slow-ish for complicated dependancy trees

That said, it has still proven useful in a number of situations.


Curently developed and tested on PostgreSQL 9.6. Might work with other versions.
 

Installation
------------

To build and install this module:

    make
    make install
    make install installcheck

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

The API provides three public user functions:

- `pg_ddlx_create(oid)` - builds SQL DDL create statements
- `pg_ddlx_drop(oid)` - builds SQL DDL drop statements
- `pg_ddlx_script(oid)` - builds SQL DDL scripts of entire dependancy trees

Currently supported object types are 
`regtype`, `regclass`, `regproc(edure)`, `regoper(ator)`, `regrole`,
`regconfig` and `regdictionary`.
You will probably want to cast object name or oid to the appropriate type.

- `pg_ddlx_create(regtype) returns text`

    Generates SQL DDL source for type `regtype`.

- `pg_ddlx_create(regclass) returns text`

    Generates SQL DDL source of a class (table or view) `regclass`.
    This also includes all associated comments, ownership, constraints, 
    indexes, triggers, rules, grants, etc...

- `pg_ddlx_create(regproc) returns text`
- `pg_ddlx_create(regprocedure) returns text`

    Generates SQL DDL source of function `regproc`.

- `pg_ddlx_create(regoper) returns text`
- `pg_ddlx_create(regoperator) returns text`

    Generates SQL DDL source of operator `regpoper`.

- `pg_ddlx_create(regrole) returns text`

    Generates SQL DDL source for role (user or group) `regrole`.
    
- `pg_ddlx_create(regconfig) returns text`

    Generates SQL DDL source for text search configuration `regconfig`.
    
- `pg_ddlx_create(regdictionary) returns text`

    Generates SQL DDL source for text search dictionary `regdictionary`.
    

There is also a convenience function to use `oid` directly, without casting:

- `pg_ddlx_create(oid) returns text`

    Generates SQL DDL source for object ID, `oid`.

- `pg_ddlx_drop(oid) returns text`

    Generates SQL DDL DROP statement for object ID, `oid`.

There is also a higher level function to build entire DDL scripts. 
Scripts include dependant objects and can get quite large.

- `pg_ddlx_script(oid) returns text`

    Generates SQL DDL script for object ID, `oid` and all it's dependants.

- `pg_ddlx_script(text) returns text`

    Generates SQL DDL script for object identified by textual sql identifier
    and all it's dependants.
    
    This works only for types, including classes such as tables and views and
    for functions. For a function, argument types need to be specified.

At the begining of a script, there are commented-out DROP statements for all dependant objects, 
so you can see them easily.

At the end of a script, there are CREATE statements to rebuild dropped dependant objects.

Note that dropping dependant tables will erase all data stored there, so use with care!
Scripts might be more useful for rebuilding layers of functions and views and such.

For example:

```sql
CREATE TABLE users (
    id int PRIMARY KEY,
    name text
);

SELECT pg_ddlx_script('users'::regclass);

CREATE TYPE my_enum AS ENUM ('foo','bar');

SELECT pg_ddlx_script('my_enum'::regtype);

SELECT pg_ddlx_script(current_role::regrole);

```

A number of other functions are provided to extract more specific objects.
Their names all begin with `pg_ddlx_`. They are used internally by the extension 
and are possibly subject to change in future versions of the extension. 
They are generally not intended to be used by the end user. 
Nevertheless, some of them are:

- `pg_ddlx_identify(oid) returns record`

    Identify an object by object ID, `oid`. This function is used a lot in others.

- `pg_ddlx_get_columns(regclass) returns setof record`

    Get columns of a class.

See file [ddl.sql](ddl.sql) and [full list of functions](test/expected/init.out) for additional details.

See file [function_usage.svg](docs/function_usage.svg) for a picture of how this is put together.

