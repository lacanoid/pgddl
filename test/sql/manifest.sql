\pset tuples_only

with
a as (
 select oid::regprocedure,obj_description(oid) from pg_proc p where proname like 'ddlx_%'
 order by obj_description(oid) is null, cast(oid::regprocedure as text) collate "C"
)
select * from a
;
