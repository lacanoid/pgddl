\pset null _null_

SET ROLE postgres;

SET client_min_messages = warning;

CREATE EXTENSION file_fdw;
CREATE EXTENSION adminpack;

COMMENT ON FOREIGN DATA WRAPPER file_fdw IS 'File wrapper';
GRANT USAGE ON FOREIGN DATA WRAPPER file_fdw to PUBLIC;
CREATE TEMPORARY TABLE t1 AS SELECT pg_file_unlink('pgddltest.tmp');
SELECT pg_file_write('pgddltest.tmp',E'Hello, World!\nThis is some text\n',false);

CREATE SERVER serv FOREIGN DATA WRAPPER file_fdw;

CREATE FOREIGN TABLE test_class_f (
  line text options ( force_not_null 'true' )
) 
SERVER serv
OPTIONS ( filename 'pgddltest.tmp', format 'text' );
COMMENT ON SERVER serv IS 'File server';
GRANT USAGE ON FOREIGN SERVER serv TO PUBLIC;
COMMENT ON FOREIGN TABLE test_class_f IS 'A Foreign table';
COMMENT ON COLUMN test_class_f.line IS 'A Line of text';
REVOKE ALL ON test_class_f FROM PUBLIC;

-- SELECT * FROM test_class_f;

SELECT ddlx_script('test_class_f'::regclass);

SELECT ddlx_create((select oid from pg_foreign_data_wrapper where fdwname='file_fdw'));

SELECT ddlx_drop((select oid from pg_foreign_data_wrapper where fdwname='file_fdw'));

SELECT ddlx_create((select oid from pg_foreign_server where srvname='serv'));

SELECT ddlx_drop((select oid from pg_foreign_server where srvname='serv'));

