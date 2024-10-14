\i test/sql/pg14.sql

SET client_min_messages TO error;

create table pubtab ( id integer, label text );

create publication pub1 for all tables;
comment on publication pub1 is 'Master Blaster';

create publication pub2 with ( publish='insert,delete', publish_via_partition_root );
alter publication pub2 add table pubtab;
alter publication pub2 add table items where (value is not null);
alter publication pub2 add table tab_generated12 (a,b,e);
comment on publication pub2 is 'vija vaja';


create publication pub3;
alter publication pub3 add tables in schema public2;
alter publication pub3 add table pubtab where (label is not null);

select ddlx_create(oid) from pg_publication;
