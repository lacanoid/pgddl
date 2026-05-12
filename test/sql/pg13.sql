\pset null _null_
\pset format unaligned
SET ROLE postgres;

alter view test_class_v rename column a to aardvark;
select replace(ddlx_create('test_class_v'::regclass),'test_class_r.','');

