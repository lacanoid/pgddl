\pset null _null_

SET client_min_messages = warning;

CREATE OR REPLACE FUNCTION abort_any_command()
RETURNS event_trigger
LANGUAGE plpgsql
  AS $$
BEGIN
  RAISE EXCEPTION 'command % is disabled', tg_tag;
END;
$$;

create event trigger ddlx_test_event_trigger
    on ddl_command_start
  when tag in ('CREATE TABLE')
execute procedure abort_any_command();

select pg_ddlx_create((
select oid from pg_event_trigger
 where evtname = 'ddlx_test_event_trigger'));
 
select pg_ddlx_drop((
select oid from pg_event_trigger
 where evtname = 'ddlx_test_event_trigger'));
 
drop event trigger ddlx_test_event_trigger;
