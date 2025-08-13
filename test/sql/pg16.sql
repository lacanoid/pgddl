\i test/sql/pg15.sql

-- test role privileges with options
begin;
  create role ddlx_test_user_9991;
  create role ddlx_test_user_9992;
  grant ddlx_test_user_9991 to ddlx_test_user_9992 with admin true, set false;

  select ddlx_create('ddlx_test_user_9991'::regrole);
rollback;
