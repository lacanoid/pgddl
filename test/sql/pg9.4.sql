\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

CREATE EXTENSION postgres_fdw;

CREATE SERVER serv2 
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host 'localhost');

CREATE USER MAPPING FOR PUBLIC 
SERVER serv2 
OPTIONS (user 'foo');

SELECT ddlx_create((select oid from pg_foreign_data_wrapper where fdwname='postgres_fdw'));
SELECT ddlx_create((select oid from pg_foreign_server where srvname='serv2'));

SELECT ddlx_create((select umid from pg_user_mappings where srvname='serv2' and usename='public'));
SELECT ddlx_drop((select umid from pg_user_mappings where srvname='serv2' and usename='public'));

------------------
CREATE VIEW test_class_v_co1 AS
SELECT * FROM test_class_v 
  WITH CHECK OPTION;
grant select on test_class_v_co1 to public;
SELECT ddlx_script('test_class_v_co1'::regclass);
SELECT ddlx_script('test_class_v_co1'::regtype);

CREATE VIEW test_class_v_co2 AS
SELECT * FROM test_class_v 
  WITH CASCADED CHECK OPTION;
grant select on test_class_v_co2 to public;
SELECT ddlx_script('test_class_v_co2'::regclass);
SELECT ddlx_script('test_class_v_co2'::regtype);
