\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

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
comment on event trigger ddlx_test_event_trigger
     is 'Test event trigger';

select ddlx_create((
select oid from pg_event_trigger
 where evtname = 'ddlx_test_event_trigger'));
 
select ddlx_drop((
select oid from pg_event_trigger
 where evtname = 'ddlx_test_event_trigger'));
 
drop event trigger ddlx_test_event_trigger;

CREATE TEXT SEARCH CONFIGURATION english1 ( PARSER = pg_catalog."default" );
COMMENT ON TEXT SEARCH CONFIGURATION english1 IS 'configuration for english language (1)';
ALTER TEXT SEARCH CONFIGURATION english1 OWNER TO postgres;

select ddlx_create('english1'::regconfig);
select ddlx_drop('english1'::regconfig);

CREATE TEXT SEARCH DICTIONARY english1_stem
  ( TEMPLATE = pg_catalog.snowball, language = 'english', stopwords = 'english' );
COMMENT ON TEXT SEARCH DICTIONARY english1_stem IS 'snowball stemmer for english language (1)';
ALTER TEXT SEARCH DICTIONARY english1_stem OWNER TO postgres;

select ddlx_create('english1_stem'::regdictionary);
select ddlx_drop('english1_stem'::regdictionary);

CREATE TEXT SEARCH CONFIGURATION simple1 ( PARSER = pg_catalog."default" );
COMMENT ON TEXT SEARCH CONFIGURATION simple1 IS 'simple configuration (1)';
ALTER TEXT SEARCH CONFIGURATION simple1 OWNER TO postgres;

select ddlx_create('simple1'::regconfig);

CREATE TEXT SEARCH DICTIONARY simple1
  ( TEMPLATE = pg_catalog.simple );
COMMENT ON TEXT SEARCH DICTIONARY simple1 
     IS 'simple dictionary: just lower case and check for stopword (1)';
ALTER TEXT SEARCH DICTIONARY simple1 OWNER TO postgres;

select ddlx_create('simple1'::regdictionary);

select ddlx_create((select oid from pg_ts_parser where prsname='default'));

select ddlx_create((select oid from pg_ts_template where tmplname='simple'));
