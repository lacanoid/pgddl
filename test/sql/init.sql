CREATE EXTENSION ddlx;
\pset tuples_only

\dx ddlx

with
a as (
 select oid::regprocedure,obj_description(oid) from pg_proc p where proname like 'ddlx_%'
 order by obj_description(oid) is null, cast(oid::regprocedure as text) collate "C"
)
select row_number() over() as i,* from a
;