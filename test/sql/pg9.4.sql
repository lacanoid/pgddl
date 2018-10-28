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
