\pset null _null_
\pset format unaligned

begin;
-- test compression
set role postgres;
create table complz ( label text );
create user ddlx_test_user_999;
alter table complz alter label set compression pglz;
--grant select on complz to public granted by ddlx_test_user_999;

select ddlx_create('complz'::regclass);

abort;
