\pset null _null_

SET client_min_messages = warning;

CREATE TABLE test_class_r (
  a serial primary key, 
  b text unique not null default e'Hello, world!\n', 
  c timestamp without time zone check(c > '2001-01-01'), 
  d timestamp with time zone,
  v tsvector
);
COMMENT ON TABLE test_class_r IS 'Comment1';
SELECT pg_ddl_script('test_class_r'::regclass);

CREATE TABLE test_class_r2 (
  i serial, 
  a int references test_class_r(a)
);
SELECT pg_ddl_script('test_class_r2'::regclass);

CREATE VIEW test_class_v AS
SELECT * FROM test_class_r 
  WITH CHECK OPTION;

SELECT pg_ddl_script('test_class_v'::regclass);

CREATE MATERIALIZED VIEW test_class_m AS
SELECT * FROM test_class_r;

SELECT pg_ddl_script('test_class_m'::regclass);

SELECT pg_ddl_script('pg_ddl_oid_info(oid)'::regprocedure);

/*
CREATE DOMAIN test_type_d text check(value is not null);
SELECT pg_ddl_script('test_type_d'::regtype);

CREATE TYPE test_type_c AS (i integer, t text, d test_type_d);
SELECT pg_ddl_script('test_type_c'::regtype);
*/


