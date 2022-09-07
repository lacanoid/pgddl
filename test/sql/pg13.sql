\i test/sql/pg12.sql

alter view test_class_v rename column a to aardvark;
select ddlx_create('test_class_v'::regclass);

