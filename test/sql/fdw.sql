\pset null _null_

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
COMMENT ON FOREIGN TABLE test_class_f IS 'Foreign table';
COMMENT ON COLUMN test_class_f.line IS 'A Line of text';
GRANT ALL ON test_class_f TO PUBLIC;

SELECT * FROM test_class_f;

SELECT pg_ddl_script('test_class_f'::regclass);
