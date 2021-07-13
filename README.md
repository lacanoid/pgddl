DDL eXtractor functions  for PostgreSQL
=======================================

This is an SQL-only extension for PostgreSQL that provides uniform functions for generating 
SQL Data Definition Language (DDL) scripts for objects created in a database. 
It contains a bunch of SQL functions  to convert PostgreSQL system catalogs 
to nicely formatted snippets of SQL DDL, such as CREATE TABLE.

Some other SQL databases support commands like SHOW CREATE TABLE or provide 
other facilities for the purpose. 

PostgreSQL currently doesn't provide overall in-server DDL extracting functions,
but rather a separate `pg_dump` program. It is an external tool to the server 
and therefore requires shell access or local installation to be of use.

PostgreSQL however already provides a number of helper functions which already greatly help 
with reconstructing DDL and are of course used by this extension.
PostgreSQL also has sophisticated query capabilities, such as CTEs and window functions 
which make this project possible by using only SQL.

Advantages over using other tools like `psql` or `pg_dump` include:

- You can use it to extract DDL with **any client** which support running plain SQL queries
- **Simple API** with just three functions. Just supply `oid`.
- With SQL you can select things to dump by using usual SQL semantics (WHERE, etc)
- Special function for creating scripts, which drop and recreate entire **dependancy trees**.
  This is useful for example, when one wishes to rename some columns in a view with dependants.
  This works particularly great with transactional DDL of Postgres.
- Created scripts are somewhat more intended to be run and copy/pasted manually by the DBA
  into other databases/scripts. This involves 
   pretty printing,
   using **idempotent DDL** where possible (preferring ALTER to CREATE), 
   creating indexes which are part of a constraint with ADD CONSTRAINT and so on.
- **No shell access** or shell commands with hairy options required (for running pg_dump), 
  just use SELECT and hairy SQL instead!
- It is entrely made out of **plain SQL functions** so you don't have to install any extra
  languages, not even PL/PgSQL! It runs on plain vanilla Postgres.

Some disadvantages:

- Not all Postgres objects and all options are supported yet. Postgres is huge. 
  This package provides support for basic user-level objects such as types, classes and functions.
  All `reg*` objects and SQL standard compliant stuff is mostly supported,
  with more fringe stuff still under constuction. 
  The intention for version 1.0 is to support all Postgres objects. 
  See [ROADMAP](ROADMAP.md) for some of what's still missing.
- It is not very well tested. While it contains a number of regression tests, these can be
  hardly considered as proofs of correctness. Be certain there are bugs. Use at your own risk!
  Do not run generated scripts on production databases without testing them first!
- It is kind of slow-ish for complicated dependancy trees

That said, it has still proven quite useful in a many situations
and is being used with a number of production databases.
Bug reports are welcome.

Curently developed and tested on PostgreSQL 10. 
Included preprocessor adapts the source to target PG version. 
Tested to install on version 9.1 and later. 
Some tests might fail on older versions. 

Installation
------------

To build this module:

    make

This builds extension for your particular version of Postgres in a file like `ddlx--0.20.sql`.

    make install
    make install installcheck

You can select a specific PostgreSQL installation:

    make PG_CONFIG=/some/where/bin/pg_config
    make PG_CONFIG=/some/where/bin/pg_config install
    make PG_CONFIG=/some/where/bin/pg_config installcheck
    make PGPORT=5432 PG_CONFIG=/usr/lib/postgresql/10/bin/pg_config clean install installcheck

Make sure you set the connection parameters like `PGPORT` right for testing.

And finally inside the database:

    CREATE EXTENSION ddlx;

It you use multiple schemas, you will need to have variable `search_path` 
set appropriately for the extension to work. To make it work with any value of
`search_path`, you can install the extension in the `pg_catalog` schema:

    CREATE EXTENSION ddlx SCHEMA pg_catalog;

This of course requires superuser privileges.

If for some reason you are unable to use this as an extension, you can simply load generated SQL file
into your database by any regular means:

    $ psql my_database -1 -f ddlx--0.20.sql

Using
-----

The API provides three public user functions:

- `ddlx_create(oid, options)` - builds SQL DDL create statements
- `ddlx_drop(oid, options)`   - builds SQL DDL drop statements
- `ddlx_script(oid, options)` - builds SQL DDL scripts of entire dependancy trees

These are useful with various `reg*` [object identifier types](https://www.postgresql.org/docs/current/datatype-oid.html) 
supported by Postgres, which are then automatically cast to `oid`. Options can be ommited.

You can use them simply by casting object name (or oid) to some `reg*` type:

    SELECT ddlx_create('my_table'::regclass);
    
    SELECT ddlx_create('my_type'::regtype);

    SELECT ddlx_create('my_function'::regproc);

    SELECT ddlx_create(current_role::regrole);

    SELECT ddlx_create('+(int,int)'::regoperator);

All object identifier types are supported:
`regclass`,`regtype`,`regrole`,`regnamespace`,`regproc`,`regprocedure`,
`regoper`,`regoperator`,`regconfig`,`regdictionary`,`regcollation`

For objects without object identifier types, you have to find object ID `oid` first.
You can use something like:

    SELECT ddlx_create(oid) FROM pg_foreign_data_wrapper WHERE fdwname='postgres_fdw';

    SELECT ddlx_create(oid) FROM pg_database WHERE datname=current_database();

Options are optional and are passed as text array, for example `{ine,nodcl}`. They specify extra options on how things in created DDL should be. Currently supported options are:

* `drop` - include DROP statements in a script. These are otherwise commented out.
* `noalter` - include neither `alter` nor DCL (grant) statements
* `noowner` - do not include `alter set owner`
* `nogrants` - do not include grants
* `nodcl` - do not include `alter set owner` nor `grant`
* `owner` - always include `alter set owner`. It is ommited when owner is current user otherwise.
* `ine` - include `if not exists` in bunch of places
* `ie` - include `if exists` in a bunch of places

Drop statements are created with `ddlx_drop()` function.	

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

DDL statements generated have identifiers schema-prefixed for stuff not in current schema.
If you want to dump a whole namespace without schema names, set `search_path` before calling `ddlx_script`().

Note that dropping dependant tables will erase all data stored there, so use with care!
Scripts might be more useful for rebuilding layers of functions and views and such.

For example:

    CREATE TABLE users (
        id int PRIMARY KEY,
        name text
    );

    SELECT ddlx_script('users');

    CREATE TYPE my_enum AS ENUM ('foo','bar');

    SELECT ddlx_script('my_enum');

    SELECT ddlx_script(current_role::regrole);

A number of other functions are provided to extract more specific objects.
Their names all begin with `ddlx_`. They are used internally by the extension 
and are possibly subject to change in future versions of the extension. 
They are generally not intended to be used by the end user. 
Nevertheless, some of them are:

- `ddlx_identify(oid) returns record`

    Identify an object by object ID, `oid`. Searches all supported system catalogs.
    This function is used a lot by others in this extension.

- `ddlx_describe(regclass) returns setof record`

    Get columns of a class.

- `ddlx_definitions(oid) returns record`

    Get individual parts of of object definition, 
    such as: bare, comment, owner, storage, defaults, settings, constraints, indexes, triggers, rules, rls, grants.

- `ddlx_create_class(regclass) returns text`

    Get bare-bones (pre-data) SQL DDL CREATE statement for class object.
    This includes column definitions, not null and comments.

- `ddlx_alter_class(regclass) returns text`

    Get additional (post-data) SQL DDL ALTER statements for class object.
    This includes defaults, storage parametes, constraints, indexes, triggers, rules,
    owner and grants

- `ddlx_grants(oid) returns text`

    Return GRANT statements for an object

- `ddlx_apropos(regexp) returns setof record`

    Search query bodies (functions and view definitions) matching POSIX regular expression.
```    
SELECT ddlx_create(objid) FROM ddlx_apropos('users');
```
See file [ddlx.sql](ddlx.sql) and [full list of functions](test/expected/manifest.out) for additional details.
Functions with comments are public API. The rest are intended for internal use, the purpose can
usually be inferred from the name.

See file [function_usage.svg](docs/function_usage.svg) for a picture of how this is put together.

