\i test/sql/pg13.sql

-- test compression
create table complz ( label text );
alter table complz alter label set compression lz4;

select ddlx_create('complz'::regclass);
