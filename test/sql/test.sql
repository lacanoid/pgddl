\pset null _null_

SET client_min_messages = warning;

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
SELECT pg_ddl_script('test_class_r'::regtype);
SELECT pg_ddl_script('idx1'::regclass);
SELECT pg_ddl_script('idx2'::regclass);

CREATE UNLOGGED TABLE test_class_r2 (
  i  serial, 
  a  int,
  cc char(20),
  vv varchar(20),
  n  numeric(10,2),
  constraint "blah" foreign key (a) references test_class_r(a) deferrable initially deferred
);
alter table test_class_r2 set with oids;
SELECT pg_ddl_script('test_class_r2'::regclass);

CREATE VIEW test_class_v AS
SELECT * FROM test_class_r 
  WITH CHECK OPTION;

SELECT pg_ddl_script('test_class_v'::regclass);
SELECT pg_ddl_script('test_class_v'::regtype);

CREATE MATERIALIZED VIEW test_class_m AS
SELECT * FROM test_class_r;
create unique index test_class_mi ON test_class_m (a);

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

create type test_type_e as enum ('foo','bar','baz','qux');
comment on type test_type_e is 'my enum';
select pg_ddl_script('test_type_e'::regtype);

create domain test_type_d numeric(10,2) check(value is not null) check(value>6) default 7;
comment on type test_type_d is 'my domain';
select pg_ddl_script('test_type_d'::regtype);

create type test_type_c as (i integer, t text, d test_type_d);
comment on type test_type_c is 'my class type';
comment on column test_type_c.i is 'my class class column i';
select pg_ddl_script('test_type_c'::regtype);
select pg_ddl_script('test_type_c'::regclass);

create sequence test_type_S increment 4 start 2;
comment on sequence test_type_S is 'interleave';
select pg_ddl_script('test_type_S'::regclass);

create table test_collation (
	id serial,
	c text collate "C" not null,
	en text collate "en_US",
	t text
);
select pg_ddl_script('test_collation'::regclass);


