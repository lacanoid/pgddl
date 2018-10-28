select ddlx_create(oid) from pg_am where amname = 'btree';
select ddlx_drop(oid) from pg_am where amname = 'btree';

