\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

create type test_type_e as enum ('foo','bar','baz','qux');
comment on type test_type_e is 'my enum';
select pg_ddlx_script('test_type_e'::regtype);

create domain test_type_d numeric(10,2) check(value is not null) check(value>6) default 7;
comment on type test_type_d is 'my domain';
select pg_ddlx_script('test_type_d'::regtype);

create type test_type_c as (i integer, t text, d test_type_d);
comment on type test_type_c is 'my class type';
comment on column test_type_c.i is 'my class class column i';
select pg_ddlx_script('test_type_c'::regtype);
select pg_ddlx_script('test_type_c'::regclass);

create domain test_collation_d text collate "C" default '***';
select pg_ddlx_script('test_collation_d'::regtype);

select pg_ddlx_script('int'::regtype);
select pg_ddlx_script('int[]'::regtype);
select pg_ddlx_script('uuid'::regtype);
select pg_ddlx_script('text'::regtype);
select pg_ddlx_script('xml'::regtype);

select pg_ddlx_script('daterange'::regtype);


select pg_ddlx_script('=(integer,integer)'::regoperator);
select pg_ddlx_script('=(text,text)'::regoperator);
