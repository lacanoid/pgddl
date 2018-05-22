\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

select ddlx_create(oid) from pg_cast where castsource = 'text'::regtype order by casttarget;

select ddlx_create(oid) from pg_collation where collname in ('default','C','POSIX') order by collname;
