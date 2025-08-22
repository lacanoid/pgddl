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

PostgreSQL however already provides a number of helper functions which greatly help 
with reconstructing DDL and are of course used by this extension.
PostgreSQL also has sophisticated query capabilities, such as common table expressions and window functions 
which make this project possible by using only SQL.

Advantages over using other tools like `psql` or `pg_dump` include:

- You can use it to extract DDL with **any client** which support running plain SQL queries
- **Simple API** with just three functions. Just supply `oid`.
- **No shell access** or shell commands with hairy options required (for running pg_dump), 
  just use SELECT and hairy SQL instead!
- With SQL you can select things to dump by using **usual SQL semantics** (WHERE, etc)
- Special function for creating scripts, which drop and recreate entire **dependancy trees**.
  This is great when you need to edit a table, then a view, then a function that uses the view, 
  then a function that returns SETOF.
  It works particularly well with the transactional DDL of Postgres.
- Created scripts are mostly intended to be run and copy/pasted manually by the DBA
  into other databases/scripts, such as a database upgrade scripts. It attempts to strike
  a reasonable balance between detail and clutter.
  This involves 
   pretty printing,
   using **idempotent DDL** where possible (preferring ALTER to CREATE), 
   creating indexes which are part of a constraint with ADD CONSTRAINT and so on.
- It is entrely made out of **plain SQL functions** so you don't have to install any extra
  languages, not even PL/PgSQL! It runs on plain vanilla Postgres.

Some disadvantages:

- Not all Postgres objects and all options are supported yet. Postgres is huge. 
  This package provides support for basic user-level objects such as types, classes and functions.
  Currently most objects are at least somewhat supported but not all options are.
  The intention is for version 1.0 is to support all objects and options. 
  See [ROADMAP](ROADMAP.md) for some of what is still missing.
- It is not very well tested. While it contains a number of regression tests, these can be
  hardly considered as proofs of correctness. Be certain there are bugs. Use at your own risk!
  In fact, generated scripts might not run at all.
  Do not run them on production databases without inspecting and testing them first!
- It is kind of slow-ish for complicated dependancy trees

That said, it has still proven quite useful in a many situations
and is being used with a number of production databases.
Bug reports are welcome.

If support for your favorite Postgres feature is broken or missing, please let us know and we will put some focus on it.

Curently developed and tested on PostgreSQL 13. 
Included preprocessor adapts the source to target PG version. 
Tested to install on version 9.1 and later. 
Some tests might fail on older versions. 

Installation
------------

To build this module:

    make

This builds extension for your particular version of Postgres in a file like `ddlx--0.30.sql`.

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

    $ psql my_database -1 -f ddlx--0.30.sql

Using
-----

The API provides three main public user functions:

- `ddlx_create(oid, options)` - builds SQL DDL create statements
- `ddlx_drop(oid, options)`   - builds SQL DDL drop statements
- `ddlx_script(oid, options)` - builds SQL DDL scripts of entire dependancy trees

For other functions see below.

These are useful with various `reg*` [object identifier types](https://www.postgresql.org/docs/current/datatype-oid.html) 
supported by Postgres, which are then automatically cast to `oid`. Options can be ommited.

You can use them simply by casting object name (or oid) to some `reg*` type:

    SELECT ddlx_create('my_table'::regclass,'{ine}');
    
    SELECT ddlx_create('my_type'::regtype,'{noowner}');

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

* `drop` - include `drop` statements in a script. These are otherwise commented out.
* `nodrop` - omit `drop` statements from a script entirely
* `owner` - always include `alter set owner`. Otherwise this is omitted when object owner is the same as the current user.
* `noowner` - do not include `alter set owner` statements
* `nogrants` - do not include `grant` statements
* `nodcl` - include neither `alter set owner` nor grants
* `noalter` - include neither `alter` nor DCL (grant) statements
* `ine` - add `if not exists` in bunch of places
* `ie` - add `if exists` in a bunch of places
* `ext` - include extension contents instead of `create extension`.
* `lite` - move defaults and constraints into `create table` statement, omit some other Postgres specific stuff (SQLite compatibility)
* `nowrap` - do not wrap scripts with `BEGIN` and `END`
* `nopartitions` - do not include table partitions in a script
* `comments` - include all comments, even if null
* `nocomments` - do not include any comments
* `nostorage` - do not include storage settings
* `noconstraints` - do not include constraints
* `noindexes` - do not include indexes
* `nosettings` - do not include settings
* `notriggers` - do not include triggers
* `grantor` - include grantor in grant statements
* `data` - attempt to preserve table data, really only makes sense when used together with `drop`

Drop statements are created with `ddlx_drop()` function.	

- `ddlx_drop(oid) returns text`

    Generates SQL DDL DROP statement for object ID, `oid`.

There is also a higher level function to build entire DDL scripts. 
Scripts include dependant objects and subpartitions and can get quite large.

- `ddlx_script(oid[,options]) returns text`

    Generates SQL DDL script for object ID, `oid` and all it's dependants.

- `ddlx_script(text[,options]) returns text`

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

### Example

    CREATE TABLE users (
        id int PRIMARY KEY,
        name text
    );

    SELECT ddlx_script('users');

    CREATE TYPE my_enum AS ENUM ('foo','bar');

    SELECT ddlx_script('my_enum');

    SELECT ddlx_script(current_role::regrole);

### Additional functions

A number of other functions are provided to extract more specific objects.
Their names all begin with `ddlx_`. They are used internally by the extension 
and are possibly subject to change in future versions of the extension. 
They are generally not intended to be used by the end user. 
Nevertheless, some of them are:

- `ddlx_identify(oid) returns table(oid, classid, name, namespace, owner, sql_kind, sql_identifier, acl)`

    Identify an object by object ID, `oid`. Searches all supported system catalogs.

- `ddlx_describe(regclass) returns table`

    Get columns of a class.

- `ddlx_definitions(oid) returns table(oid, classid, sql_kind, sql_identifier, base_ddl, comment, owner,storage, defaults, settings, constraints, indexes, triggers, rules, rls, grants)`

    Get individual parts of object definition, 
    such as: base_ddl, comment, owner, storage, defaults, settings, constraints, indexes, triggers, rules, rls, grants.

- `ddlx_createonly(oid [,options]) returns text`

    Get SQL DDL statements to create an object, typically before the data is loaded.
    For classes, this includes base_ddl, comments, owner, storage, defaults and settings.

- `ddlx_alter(oid [,options]) returns text`

    Get additional SQL DDL ALTER statements for an object, typically after the data is loaded.
    For classes, this includes defaults, storage parametes, constraints, indexes, triggers, rules,
    owner and grants.

- `ddlx_grants(oid) returns text`

    Return GRANT statements for an object

- `ddlx_apropos(regexp) returns table(classid, objid, sql_identifier, sql_kind, language, owner, comment, retset, namespace, name, source)`

    Search query bodies (functions and view definitions) matching POSIX regular expression.
```    
SELECT ddlx_create(objid) FROM ddlx_apropos('users');

SELECT * FROM ddlx_apropos('users') JOIN ddlx_identify(objid) ON true;

SELECT * FROM ddlx_apropos('users') JOIN ddlx_definitions(objid) ON true;
```
See file [ddlx.sql](ddlx.sql) and [full list of functions](test/expected/manifest.out) for additional details.
Functions with comments are public API. The rest are intended for internal use, the purpose can
usually be inferred from the name.

See file [function_usage.svg](docs/function_usage.svg) for a picture of how this is put together.

