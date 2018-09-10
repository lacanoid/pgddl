\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

select ddlx_create(oid) from pg_cast where castsource = 'text'::regtype order by casttarget;

CREATE COLLATION "POSIX++" (
  LC_COLLATE = 'POSIX',
  LC_CTYPE = 'POSIX'
);
COMMENT ON COLLATION "POSIX++" IS 'standard POSIX++ collation';

select ddlx_create(oid) from pg_collation where collname in ('POSIX++') order by collname;

CREATE DEFAULT CONVERSION "ascii_to_utf8++"
  FOR 'SQL_ASCII' TO 'UTF8' FROM ascii_to_utf8;
COMMENT ON CONVERSION "ascii_to_utf8++" IS 'conversion++ for SQL_ASCII to UTF8';

select ddlx_create(oid) from pg_conversion where conname in ('ascii_to_utf8++') order by conname;

select ddlx_grants('test_class_r'::regclass::oid);

select ddlx_create(oid) from pg_am where amname = 'btree';
