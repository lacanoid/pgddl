CREATE EXTENSION ddl;
\pset tuples_only

\dx ddl

select oid::regprocedure,obj_description(oid) from pg_proc p where proname like 'pg_ddlx_%'
order by obj_description(oid) is null, cast(oid::regprocedure as text) collate "C";