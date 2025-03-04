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
grant select,insert,update,delete,references,trigger,truncate on test_class_r to public;
select classid::regclass, sql_kind, sql_identifier from ddlx_identify('test_class_r'::regtype);
select classid::regclass, sql_kind, sql_identifier from ddlx_identify('test_class_r'::regclass);
alter table test_class_r alter h set storage external;

create trigger aaaa before 
update on test_class_r
   for each row when (old.* is distinct from new.*) execute procedure trig('AAAA');
alter table test_class_r disable trigger aaaa;

create unique index idx1 on test_class_r (lower(b)) where b is not null;
create index idx2 on test_class_r using gin (v);
create index idx3 on test_class_r(g) with (fillfactor=50);
cluster test_class_r using idx3;

SELECT replace(ddlx_script('test_class_r'::regclass,'{owner}'),'FUNCTION','PROCEDURE') as ddlx_script;
cluster test_class_r using test_class_r_pkey;
SELECT replace(ddlx_script('test_class_r'::regtype,'{owner}'),'FUNCTION','PROCEDURE') as ddlx_script;
SELECT ddlx_script('idx1'::regclass,'{owner}');
SELECT ddlx_script('idx2'::regclass,'{owner}');

CREATE UNLOGGED TABLE test_class_r2 (
  i  serial, 
  a  int,
  cc char(20),
  vv varchar(20),
  n  numeric(10,2),
  constraint "blah" foreign key (a) references test_class_r(a)
 );
-- alter table test_class_r2 set with oids;
alter table test_class_r2 add  constraint "blah2" foreign key (a) references test_class_r(a) deferrable initially deferred not valid;
SELECT ddlx_script('test_class_r2'::regclass);

CREATE VIEW test_class_v AS
SELECT * FROM test_class_r;
grant select on test_class_v to public;
SELECT replace(ddlx_script('test_class_v'::regclass,'{owner}'),'test_class_r.','');
SELECT replace(ddlx_script('test_class_v'::regtype,'{owner}'),'test_class_r.','');

CREATE VIEW test_class_v2 AS
SELECT * FROM test_class_v;
grant select (a,b,c) on test_class_v2 to public;
SELECT regexp_replace(ddlx_script('test_class_v'::regclass,'{owner}'),'test_class_[rv]\.','','g');

CREATE MATERIALIZED VIEW test_class_m AS
SELECT * FROM test_class_r;
create unique index test_class_mi ON test_class_m (a);
grant select on test_class_m to public;

SELECT replace(ddlx_script('test_class_m'::regclass,'{owner}'),'test_class_r.','');;

select sql_kind, sql_identifier from ddlx_identify('ddlx_identify(oid)'::regprocedure);

create function funfun(a int, b text default null, out c numeric, out d text) returns setof record as 
$$ select 3.14, 'now'::text $$ language sql cost 123 rows 19
set xmloption = content
;
comment on function funfun(int,text) is 'Use more comments!';

select * from funfun(1);
SELECT ddlx_script('funfun'::regproc);
SELECT ddlx_script('funfun(int,text)'::regprocedure,'{owner}');

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

select replace(ddlx_script('test_class_v_opt2'::regclass),'test_class_v.','');;

select replace(ddlx_script('test_class_v_opt2'::regclass::oid),'test_class_v.','');;
select replace(ddlx_script('test_class_v_opt2'),'test_class_v.','');;

create or replace function test_proc_1() returns text as
$$ select 'Hello, world!'::text $$ language sql;

create or replace function test_proc_2(integer) returns text strict as
$$ select b from test_class_r where a = $1 $$ language sql;

select ddlx_script('test_proc_1'::regproc);
select ddlx_script('test_proc_1'::regproc::oid);
select ddlx_script('test_proc_1()');

CREATE AGGREGATE test_proc_agg_1(text) (
    SFUNC = textcat,
    STYPE = text
);

select ddlx_script('test_proc_agg_1'::regproc);

/*
CREATE AGGREGATE test_proc_agg_2(anyelement) (
    SFUNC = array_append,
    STYPE = anyarray,
    INITCOND = '{}'
);

select ddlx_script('test_proc_agg_2'::regproc);
*/

-----
create table test_parent ( i serial );
create table test_child () inherits (test_parent);
select ddlx_create('test_parent'::regclass); 
select ddlx_create('test_child'::regclass); 


-----
-- test pre-data and post-data functions

select ddlx_createonly('test_class_r'::regclass);
select replace(ddlx_alter('test_class_r'::regclass),'FUNCTION','PROCEDURE') as ddlx_alter;

-----
-- test 'lite' option
select ddlx_create('test_class_r'::regclass,'{lite}');
select ddlx_createonly('test_class_r'::regclass,'{lite}');
select ddlx_alter('test_class_r'::regclass,'{lite}');


-----
-- test referential constraints to the same table
create table ref1 (
    id integer unique REFERENCES ref1(id)
);
create table ref2 (
    id integer REFERENCES ref1(id)
);
select ddlx_script('ref1'::regclass);

-----
-- test grants on seqeunces
create sequence my_sequence;
grant usage on SEQUENCE my_sequence to public;
select ddlx_grants('my_sequence'::regclass);
select ddlx_grants('my_sequence'::regclass::oid);
drop sequence my_sequence;
