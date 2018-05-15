\pset null _null_

SET ROLE postgres;

SET client_min_messages = warning;

CREATE EXTENSION file_fdw;
CREATE EXTENSION adminpack;

CREATE TEMPORARY TABLE t1 AS SELECT pg_file_unlink('pgddltest.tmp');
SELECT pg_file_write('pgddltest.tmp',E'Hello, World!\nThis is some text\n',false);

CREATE SERVER serv FOREIGN DATA WRAPPER file_fdw;

CREATE FOREIGN TABLE test_class_f (
  line text
) 
SERVER serv
OPTIONS ( filename 'pgddltest.tmp', format 'text' );
COMMENT ON FOREIGN TABLE test_class_f IS 'A Foreign table';
COMMENT ON COLUMN test_class_f.line IS 'A Line of text';
GRANT ALL ON test_class_f TO PUBLIC;

SELECT * FROM test_class_f;

SELECT ddlx_script('test_class_f'::regclass);

SELECT ddlx_create((select oid from pg_foreign_data_wrapper where fdwname='file_fdw'));

SELECT ddlx_drop((select oid from pg_foreign_data_wrapper where fdwname='file_fdw'));

SELECT ddlx_create((select oid from pg_foreign_server where srvname='serv'));

SELECT ddlx_drop((select oid from pg_foreign_server where srvname='serv'));

CREATE EXTENSION postgres_fdw;

CREATE SERVER serv2 
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host 'localhost');

CREATE USER MAPPING FOR PUBLIC 
SERVER serv2 
OPTIONS (user 'foo');

SELECT ddlx_create((select oid from pg_foreign_data_wrapper where fdwname='postgres_fdw'));
SELECT ddlx_create((select oid from pg_foreign_server where srvname='serv2'));

SELECT ddlx_create((select umid from pg_user_mappings where srvname='serv2' and usename='public'));
SELECT ddlx_drop((select umid from pg_user_mappings where srvname='serv2' and usename='public'));
