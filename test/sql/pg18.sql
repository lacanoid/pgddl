begin;
-- test new virtual generated columns
create table aa (
  id integer,
  a  numeric,
  b numeric,
  c numeric generated always as (a+b) stored,
  d numeric generated always as (a-b)
);
select ddlx_create('aa'::regclass);
abort;
\i test/sql/pg17.sql
