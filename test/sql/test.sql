\pset null _null_

SET client_min_messages = warning;

SELECT pg_ddl_script('int'::regtype::oid::regclass);
select kind, sql_identifier from pg_ddl_oid_info('pg_ddl_oid_info(oid)'::regprocedure);

create function trig() returns trigger as 
$$begin return old; end $$
language plpgsql;

CREATE TABLE test_class_r (
  a serial primary key, 
  b text unique not null default e'Hello, world!\n', 
  c timestamp without time zone check(c > '2001-01-01'), 
  d timestamp with time zone,
  v tsvector
);
COMMENT ON TABLE test_class_r IS 'Comment1';
select kind, sql_identifier from pg_ddl_oid_info('test_class_r'::regclass);

create trigger aaaa before 
update on test_class_r
   for each row when (old.* is distinct from new.*) execute procedure trig('AAAA');

create unique index idx1 on test_class_r (lower(b)) where b is not null;
create index idx2 on test_class_r using gin (v);

SELECT pg_ddl_script('test_class_r'::regclass);

CREATE UNLOGGED TABLE test_class_r2 (
  i serial, 
  a int references test_class_r(a)
);
alter table test_class_r2 set with oids;
SELECT pg_ddl_script('test_class_r2'::regclass);

CREATE VIEW test_class_v AS
SELECT * FROM test_class_r 
  WITH CHECK OPTION;

SELECT pg_ddl_script('test_class_v'::regclass);

CREATE MATERIALIZED VIEW test_class_m AS
SELECT * FROM test_class_r;

SELECT pg_ddl_script('test_class_m'::regclass);

select kind, sql_identifier from pg_ddl_oid_info('pg_ddl_oid_info(oid)'::regprocedure);
SELECT pg_ddl_script('pg_ddl_oid_info(oid)'::regprocedure);

create function funfun(a int, b text default null, out c numeric, out d text) returns setof record as 
$$ select 3.14, 'now'::text $$ language sql cost 123 rows 19
set xmloption = content
;
comment on function funfun(int,text) is 'Use more comments!';

select * from funfun(1);
SELECT pg_ddl_script('funfun'::regproc);

/*
CREATE DOMAIN test_type_d text check(value is not null);
SELECT pg_ddl_script('test_type_d'::regtype);

CREATE TYPE test_type_c AS (i integer, t text, d test_type_d);
SELECT pg_ddl_script('test_type_c'::regtype);
*/



