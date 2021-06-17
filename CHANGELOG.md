Version 0.20
------------
- new internal function `ddlx_definitions()` to return different parts of object definition
- `ddlx_create()` now uses this
- implemented option `ine` in some places for `IF NOT EXISTS`
- implemented option `ie` in some places for `IF EXISTS`
- implemented option `drop` to include drop statements in a script.
- demoted a bunch of overloaded `ddlx_create()` functions, now it all goes through `ddlx_create(oid)`
- `ddlx_grants()` is now consistent

Version 0.19
------------
- `ddlx_apropos()` now uses POSIX instead of SQL regular expressions
- Postgres 14 test fail fix

Version 0.18
------------
- bug fix in create_event_trigger()
- ddlx_identify() now more correctly identifies regtype vs regclass objects
- exclude objects from extensions unless 'ext' option is specified
- added .travis.yml

Version 0.17
------------
- improved support for Postgres 13 (added missing test files)
- updated tests

Version 0.16
------------
- support for GENERATED columns

Version 0.15
------------
- added parameter ddlx_options text[] to a bunch of functions
- bug fixes WRT dropped attributes
- added ddlx_apropos(pattern) function to search queries (functions and views) matching a pattern
- support for ALTER TABLE ENABLE/FORCE ROW LEVEL SECURITY
- support for publications and subscriptions
- pg12 test fixes

Version 0.14
------------
- improved for Postgres 12 (WITH OIDS is deprecated)

Version 0.13
------------
- support for ALTER TABLE ALTER COLUMN SET configurations (attoptions)
- support for ALTER TABLE ALTER COLUMN SET STATISTICS (attstattarget)
- support for materialized views WITH NO DATA
- some support for tables OF type (still missing not nulls)
- better handling of SERIAL columns, particularly in scripts
- CLUSTER now also works for constraint indexes + name bugfix
- ddlx_create(regrole) now works for non-superusers + other bugfixes
- partition key now displayed correctly thanks to pg_get_partkeydef(oid)
- slightly reworked some of the queries in ddlx_get_* functions to make them a lot faster :)
- added tests for index fillfactor and not valid constraints
- removal of obsolete pg_attrdef.adsrc
- misc bug fixes: operator name, better 9.1 compatibility

Version 0.12
------------
- support CLUSTER table USING index
- support for disabled triggers
- support for policies (row level security)
- support for statistics
- support for grants on foreign data wrappers and servers
- support for ALTER DATABASE SET configurations
- some support for partitioning
- some support for operator classes, pg_amproc, pg_amop
- added new ddlx_alter_class(regclass) (internal) function, for post data DDL
- more use of format() function for speed and readability
- slight refactoring removing some code duplication

Version 0.11
------------
- support for column grants
- support for fdw options on columns
- function ddlx_get_dependants_recursive() rolled into ddlx_get_dependants()
- removed redundant column 'kind' from ddlx_identify()
- bug fix in create enum

Version 0.10
------------
- pg 11 compatible, but it runs on older versions from 9.1 on
- fix ddlx_script(text) dependants bug
- support for languages and transforms
- support for databases
- support for tablespaces
- support for rules
- support for column storage parameters
- some support for access methods
- some support for operator families
- added column 'acl' to ddlx_identify()
- new ddlx_grants(oid) function
- ddlx_get_dependants_recursive() is faster
- better storage parameter output in ddlx_describe()
- preprocessor for specific pg version
- more use of format() function for speed and readability
- some code cleanup for speed and readability
- bug fixes

Version 0.9
-----------
- renamed extension to ddlx
- API rename pg_ddlx -> ddlx (it is long enough)
- support for event triggers
- support for foreign data wrappers
- support for foreign servers
- support for foreign user mappings
- support for text search configurations (regconfig)
- support for text search dictionaries (regdictionary)
- support for text search parsers and templates
- support for casts
- support for collations
- support for conversions
- permission fixes for non superusers
- renamed pg_ddlx_get_columns function to ddlx_describe
- improved script formatting
- improved regression tests
- bug fixes for ddlx_drop

Version 0.8
-----------
- API rename pg_ddl -> pg_ddlx (think DDL eXtractor)
- add pg_ddlx_create(oid) and pg_ddlx_drop(oid) functions to API
- pg_ddlx_script() now also includes dependant objects
  and wraps the whole thing with BEGIN/END
- support for regoper, regoperator
- support for regnamespace (grants are missing!)
- fix pg_ddlx_get_triggers() (TRUNCATE and INSTEAD supported)
- more slight banner changes
- more use of format() function for speed and readability

Version 0.7
-----------
- pg_ddl_oid_info() renamed to pg_ddl_identify() and improved with new types
- pg_ddl_script() now works for oid and text arguments
- pg_ddl_script(oid) also handles constraints, triggers and defaults
- slight banner change
- use of format() function for speed and readability
- added pg_ddl_get_dependants() internal function
- aggregate support (not for ordered yet!)

Version 0.6
-----------
- support for regroles
- support for collations on domains
- support for range types

Version 0.5
-----------
- support for foreign tables
- support for reloptions (alter view set)
- bugfix when printing [] before typmod

Version 0.4
-----------
- initial support for base types
- do not dump owner grants on classes
- use CREATE OR REPLACE in extension
- empty index name bug fix

Version 0.3
-----------
- support for column collations

Version 0.2
-----------
- bug fixes
- added META.json

Version 0.1
-----------
- initial version
