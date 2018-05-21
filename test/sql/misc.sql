\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

select ddlx_create(oid) from pg_cast;
