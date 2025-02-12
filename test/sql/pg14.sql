\i test/sql/pg13.sql

begin;
-- test compression
create table complz ( label text );
create user ddlx_test_user_999;
alter table complz alter label set compression lz4;
--grant select on complz to public granted by ddlx_test_user_999;

select ddlx_create('complz'::regclass);

abort;
