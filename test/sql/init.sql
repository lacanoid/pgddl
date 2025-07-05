CREATE EXTENSION ddlx;
\pset tuples_only

select extname,extversion,nspname,obj_description(e.oid)
  from pg_extension e join pg_namespace n on n.oid=extnamespace
 where extname='ddlx';

