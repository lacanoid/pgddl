\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

select ddlx_create(oid) from pg_am where amname = 'btree';
select ddlx_drop(oid) from pg_am where amname = 'btree';

