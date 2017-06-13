\pset null _null_
\pset format unaligned

SET client_min_messages = warning;

select kind, sql_identifier from pg_ddl_identify('pg_ddl_identify(oid)'::regprocedure);

create function trig() returns trigger as 
$$begin return old; end $$
language plpgsql;

CREATE TABLE test_class_r (
  a serial primary key, 
  b text unique not null default e'Hello, world!\n', 
  c timestamp without time zone check(c > '2001-01-01'), 
  d timestamp with time zone,
  e numeric(30)[],
  f numeric(10,2)[],
  g varchar(10)[],
  h varchar[],
  v tsvector
);
COMMENT ON TABLE test_class_r IS 'Comment1';
grant all on test_class_r to public;
select kind, sql_identifier from pg_ddl_identify('test_class_r'::regclass);

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

select kind, sql_identifier from pg_ddl_identify('pg_ddl_identify(oid)'::regprocedure);
SELECT pg_ddl_script('pg_ddl_identify(oid)'::regprocedure);

create function funfun(a int, b text default null, out c numeric, out d text) returns setof record as 
$$ select 3.14, 'now'::text $$ language sql cost 123 rows 19
set xmloption = content
;
comment on function funfun(int,text) is 'Use more comments!';

select * from funfun(1);
SELECT pg_ddl_script('funfun'::regproc);

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

create view test_class_v_opt1 with (security_barrier) 
as select * from test_class_v order by 1;
create view test_class_v_opt2 
as select * from test_class_v order by 1;
alter  view test_class_v_opt2 set (security_barrier='true');

select pg_ddl_script('test_class_v_opt1'::regclass);
select pg_ddl_script('test_class_v_opt2'::regclass);

select pg_ddl_script('test_class_v_opt2'::regclass::oid);
select pg_ddl_script('test_class_v_opt2');

create or replace function test_proc_1() returns text as
$$ select 'Hello, world!'::text $$ language sql;

select pg_ddl_script('test_proc_1'::regproc);
select pg_ddl_script('test_proc_1'::regproc::oid);
select pg_ddl_script('test_proc_1()');
