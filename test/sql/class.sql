\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

select sql_kind, sql_identifier from ddlx_identify('ddlx_identify(oid)'::regprocedure);

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
alter table test_class_r alter e set (n_distinct=10);
alter table test_class_r alter f set (n_distinct=100);
alter table test_class_r alter h set statistics 50;
grant all on test_class_r to public;
select sql_kind, sql_identifier from ddlx_identify('test_class_r'::regclass);
alter table test_class_r alter h set storage external;

create trigger aaaa before 
update on test_class_r
   for each row when (old.* is distinct from new.*) execute procedure trig('AAAA');
alter table test_class_r disable trigger aaaa;

create unique index idx1 on test_class_r (lower(b)) where b is not null;
create index idx2 on test_class_r using gin (v);
create index idx3 on test_class_r(g) with (fillfactor=50);
cluster test_class_r using idx3;

SELECT ddlx_script('test_class_r'::regclass);
cluster test_class_r using test_class_r_pkey;
SELECT ddlx_script('test_class_r'::regtype);
SELECT ddlx_script('idx1'::regclass);
SELECT ddlx_script('idx2'::regclass);

CREATE UNLOGGED TABLE test_class_r2 (
  i  serial, 
  a  int,
  cc char(20),
  vv varchar(20),
  n  numeric(10,2),
  constraint "blah" foreign key (a) references test_class_r(a)
 );
alter table test_class_r2 set with oids;
alter table test_class_r2 add  constraint "blah2" foreign key (a) references test_class_r(a) deferrable initially deferred not valid;
SELECT ddlx_script('test_class_r2'::regclass);

CREATE VIEW test_class_v AS
SELECT * FROM test_class_r;
grant select on test_class_v to public;
SELECT ddlx_script('test_class_v'::regclass);
SELECT ddlx_script('test_class_v'::regtype);

CREATE VIEW test_class_v2 AS
SELECT * FROM test_class_v;
grant select (a,b,c) on test_class_v2 to public;
SELECT ddlx_script('test_class_v'::regclass);

CREATE MATERIALIZED VIEW test_class_m AS
SELECT * FROM test_class_r;
create unique index test_class_mi ON test_class_m (a);

SELECT ddlx_script('test_class_m'::regclass);

select sql_kind, sql_identifier from ddlx_identify('ddlx_identify(oid)'::regprocedure);

create function funfun(a int, b text default null, out c numeric, out d text) returns setof record as 
$$ select 3.14, 'now'::text $$ language sql cost 123 rows 19
set xmloption = content
;
comment on function funfun(int,text) is 'Use more comments!';

select * from funfun(1);
SELECT ddlx_script('funfun'::regproc);
SELECT ddlx_script('funfun(int,text)'::regprocedure);

create sequence test_type_S increment 4 start 2;
comment on sequence test_type_S is 'interleave';
select ddlx_script('test_type_S'::regclass);

create table test_collation (
	id serial,
	c text collate "C" not null,
	t text
);
select ddlx_script('test_collation'::regclass);

create view test_class_v_opt2 
as select * from test_class_v order by 1;
alter  view test_class_v_opt2 set (security_barrier='true');

select ddlx_script('test_class_v_opt2'::regclass);

select ddlx_script('test_class_v_opt2'::regclass::oid);
select ddlx_script('test_class_v_opt2');

create or replace function test_proc_1() returns text as
$$ select 'Hello, world!'::text $$ language sql;

select ddlx_script('test_proc_1'::regproc);
select ddlx_script('test_proc_1'::regproc::oid);
select ddlx_script('test_proc_1()');

CREATE AGGREGATE test_proc_agg_1(text) (
    SFUNC = textcat,
    STYPE = text
);

select ddlx_script('test_proc_agg_1'::regproc);

CREATE AGGREGATE test_proc_agg_2(anyelement) (
    SFUNC = array_append,
    STYPE = anyarray,
    INITCOND = '{}'
);

select ddlx_script('test_proc_agg_2'::regproc);

-----
create table test_parent ( i serial );
create table test_child () inherits (test_parent);
select ddlx_create('test_parent'::regclass); 
select ddlx_create('test_child'::regclass); 
