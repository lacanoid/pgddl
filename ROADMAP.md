Introduction
------------

This started as a quick hack some years ago, when I broke my PostgreSQL database 
(must have been version 7.3 or so) so that pg_dump wouldn't dump it anymore.
Plus it couldn't handle dumping say only functions from a certain schema. 
I have since then learned how to fix my database and pg_dump got options like --schema.

But the idea of a database being able to dump itself more autonomously persisted.
After all, if LISP can do it, why not Postgres with its awesome SQL power? 
Information is all there in the system catalogs. One just needs to decipher it.

This tool uses information schema and standard SQL as much as possible, 
but for any actual practical use decoding of PostgreSQL system catalogs is required. 
Querying pg_catalog can turn out to be quite complicated for a somewhat casual SQL user.
This project attempts to collect many SQL snippets made over the years into a coherent extension.

This will hopefully help to collect the relevant SQL code for these things in one place.
Perhaps this can also be of some use to GUI tools builders and such in implementing "Extract DDL" functionality.

Tasks
-----

Support for other postgres objects:
- ✔︎ pg_amop, pg_amproc
- ✔︎ extensions
- pg_default_acl
- pg_largeobject_metadata
- pg_publication_rel
- pg_enum

Support for other missing options:
- ✔︎ comments on all objects
- ✔︎ ownership of all objects 
- ✔︎ grants on all objects
- ✔︎ grants vs current_role (who is grantor?, GRANTED BY)
- materialized view tablespace & storage parameters
- table of type not nulls
- PG14 SET COMPRESSION
- PG15 UNIQUE NULL NOT DISTINCT
- PG15 publication columns and qualifiers
- PG16 MAINTAIN privilege
- PG16 GRANT WITH INHERIT, SET
- SET STATISTICS on indexes
- ✔︎ pg_subscription not readable by non superuser
- create base type: SUBSCRIPT, PASSEDBYVALUE, LIKE,  
- create range type: MULTIRANGE_TYPE_NAME

Other:
- figure out how to elegantly separate pre-data, post-data, create, alter and dcl
- ✔︎ add `ddlx_createonly(oid)` for pre-data
- ✔︎ add `ddlx_alter(oid)` for post-data
- add `ddlx_alter_column(regclass,name)`
- group column alters together by column name
- ✔︎ handle sequences better (create if not exists)
- ✔︎ handle dependancies for types better (use shell types)
- improve dumping of comments (be quiet on NULL comments)
- optimize grants on functions
- move not nulls to constraints section
- move storage setting to pre-data section
- use ONLY when appropriate
- ✔︎ mysterious duplicates in index section for partitioned tables (see table dept_1)
- ✔︎ include table subpartitions in a script
- ✔︎ do not emit ALTER OWNER for objects owned by current role

Build and tests:
- improve and add to simple tests
- improve support for non superusers (more testing)
- ✔︎ make some tests to test if what we output actually runs, test execute them
- make some tests which compare to output of pg_dump;
  make utility for any sql file to compare the dump by pg_dump and ddlx.
  Comparison should compare actual contents, not merely text.

Options
-------

Some options as to what and how to dump stuff might be required:

* ✔︎ `DROP` - generate DROP statements
* `ALTER` - prefer ALTER to CREATE, implies 'INE' and 'IE'
* ✔︎ `DCL` - include DCL (GRANTS)
* ✔︎ `COR` - use CREATE OR REPLACE where possible 
* ✔︎ `INE` - use IF NOT EXISTS where possible
* ✔︎ `IE` - use IF EXISTS where possible
* ✔︎ `NOWRAP` - do not wrap in BEGIN / END
* ✔︎ `EXT` - include objects from extensions. Normally, these are omitted.
* `DEP` - output objects which depend on this object too
* `DATA` - add statements preserve / copy table data
* ✔︎ `NOSTORAGE` - exclude storage parameters settings
* ✔︎ `NOSETTINGS` - exclude table settings
* ✔︎ `NOPARTITIONS` - exclude table partitions
* ✔︎ `LITE` - better SQL standard compatibility (to export definitions for SQLite, for example). Moves constraints and defaults into create table section, omits a bunch of postgres specific stuff.

Other DDL dumping tools
-----------------------

### psql

Command line client `psql` contains lots of packaged SQL for handling metadata 
mainly to support code completion and various \d* commands.

### pg_dump

Database dump tool `pg_dump` contains lots of packaged SQL for handling metadata 
and especially considers various dependancies. Source code for main C source file
is is about 20000 lines long.

### pgAdmin3

PgAdmin3 DDL generation and schema handling code is an interesting 
mix of wxWidgets GUI toolkit (C++) and SQL. It requires GUI.
Generated DDLs are database administrator friendly.

### pgAdmin4

PgAdmin4 is the stuff of legends

Mailing list discussions
------------------------

- [Export the CREATE TABLE command in pure SQL](https://www.postgresql.org/message-id/flat/2bc470194b4837c1f733a4e05f569bc6%40dalibo.info)
- [SHOW CREATE](https://www.postgresql.org/message-id/flat/20190705163203.GD24679%40fetter.org)
- [get a relations DDL server-side](https://www.postgresql.org/message-id/flat/c2ce3040-a6b1-4279-97b4-fcd374ac1c60%40www.fastmail.com)
- [Adding SHOW CREATE TABLE](https://www.postgresql.org/message-id/flat/CAFEN2wxsDSSuOvrU03CE33ZphVLqtyh9viPp6huODCDx2UQkYA%40mail.gmail.com)
