DDL eXtractor functions  for PostgreSQL
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
- It is entrely made out of **plain SQL functions** so you don't have to install any extra
  languages, not even PLpgSQL! It runs on plain vanilla Postgres.
  
Some disadvantages:

- Not all Postgres objects and all options are supported yet. 
  The package provides support for basic user-level objects such as types, classes and functions.
  Initially, support for all `reg*` objects and SQL standard compliant stuff is planned first,
  with more fringe stuff coming later. See [ROADMAP](ROADMAP.md)
- It is not well tested at all. While it contains a number of regression tests, these can be
  hardly considered as proofs of correctness. Be certain there are bugs. Use at your own risk!
  Do not run generated scripts on production databases without testing them!
- It is kind of slow-ish for complicated dependancy trees

That said, it has still proven quite useful in a number of situations.


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

    CREATE EXTENSION ddlx;

It you use multiple schemas, you will need to have variable `search_path` 
set appropriately for the extension to work. To make it work with any value of
`search_path`, you can install the extension in the `pg_catalog` schema:

    CREATE EXTENSION ddlx SCHEMA pg_catalog;

This of course requires superuser privileges.

Using
-----

The API provides three public user functions:

- `ddlx_create(oid)` - builds SQL DDL create statements
- `ddlx_drop(oid)` - builds SQL DDL drop statements
- `ddlx_script(oid)` - builds SQL DDL scripts of entire dependancy trees

Currently supported object types are 
`regtype`, `regclass`, `regproc(edure)`, `regoper(ator)`, `regrole`,
`regconfig` and `regdictionary`.
You will probably want to cast object name or oid to the appropriate type.

- `ddlx_create(regtype) returns text`

    Generates SQL DDL source for type `regtype`.

- `ddlx_create(regclass) returns text`

    Generates SQL DDL source of a class (table or view) `regclass`.
    This also includes all associated comments, ownership, constraints, 
    indexes, triggers, rules, grants, etc...

- `ddlx_create(regproc) returns text`
- `ddlx_create(regprocedure) returns text`

    Generates SQL DDL source of function `regproc`.

- `ddlx_create(regoper) returns text`
- `ddlx_create(regoperator) returns text`

    Generates SQL DDL source of operator `regpoper`.

- `ddlx_create(regrole) returns text`

    Generates SQL DDL source for role (user or group) `regrole`.
    
- `ddlx_create(regconfig) returns text`

    Generates SQL DDL source for text search configuration `regconfig`.
    
- `ddlx_create(regdictionary) returns text`

    Generates SQL DDL source for text search dictionary `regdictionary`.
    

There is also a convenience function to use `oid` directly, without casting:

- `ddlx_create(oid) returns text`

    Generates SQL DDL source for object ID, `oid`. 
	This is the most general-purpose function of the bunch.
	It also works for objects other than `reg*` types specified above.

- `ddlx_drop(oid) returns text`

    Generates SQL DDL DROP statement for object ID, `oid`.

There is also a higher level function to build entire DDL scripts. 
Scripts include dependant objects and can get quite large.

- `ddlx_script(oid) returns text`

    Generates SQL DDL script for object ID, `oid` and all it's dependants.

- `ddlx_script(text) returns text`

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

SELECT ddlx_script('users'::regclass);

CREATE TYPE my_enum AS ENUM ('foo','bar');

SELECT ddlx_script('my_enum'::regtype);

SELECT ddlx_script(current_role::regrole);

```

A number of other functions are provided to extract more specific objects.
Their names all begin with `ddlx_`. They are used internally by the extension 
and are possibly subject to change in future versions of the extension. 
They are generally not intended to be used by the end user. 
Nevertheless, some of them are:

- `ddlx_identify(oid) returns record`

    Identify an object by object ID, `oid`. This function is used a lot in others.

- `ddlx_describe(regclass) returns setof record`

    Get columns of a class.

See file [ddlx.sql](ddlx.sql) and [full list of functions](test/expected/init.out) for additional details.

See file [function_usage.svg](docs/function_usage.svg) for a picture of how this is put together.

