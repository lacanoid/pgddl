\pset null _null_
\pset format unaligned

SET client_min_messages = warning;

create schema public2;

CREATE OR REPLACE FUNCTION execute(text)
 RETURNS integer
 LANGUAGE plpgsql
 STRICT
AS $function$DECLARE 
   body ALIAS FOR $1; 
   result INT; 
 BEGIN 
--   RAISE NOTICE 'Execute: %', body; 
   set search_path=public2;
   EXECUTE body; 
   GET DIAGNOSTICS result = ROW_COUNT; 
   reset search_path;
   RETURN result; 
 END; 
 $function$
;

create role pgddl_test_user2 login connection limit 100;
alter user pgddl_test_user2 password 'hello_world';

do $_$
declare ddl text;
begin
  ddl := ddlx_create('test_collation_d'::regtype,'{}');
  perform public.execute(ddl);
  ddl := ddlx_create('test_class_r_a_seq'::regclass,'{}');
  perform public.execute(ddl);
  ddl := ddlx_createonly('test_class_r'::regclass,'{}');
  perform public.execute(ddl);

  ddl := ddlx_create('pgddl_test_user2'::regrole,'{}');
  drop role pgddl_test_user2;
  perform public.execute(ddl);

end
$_$ LANGUAGE plpgsql;

drop role pgddl_test_user2;

reset role; SET ROLE postgres;

do $_$
declare ddl text;
begin
  ddl := replace(ddlx_script('public.int_t'::regtype,'{nowrap}'),'public.','');
  perform public.execute(ddl);
  ddl := ddlx_script('test_class_v'::regtype,'{nowrap}');
  perform public.execute(ddl);

  ddl := ddlx_script('test_class_v2'::regclass,'{nowrap}');
--  raise warning 'DDLX: %', ddl;
  perform public.execute(ddl);

  ddl := ddlx_script('test_class_r'::regclass,'{nowrap,drop}');
  execute ddl;
end
$_$ LANGUAGE plpgsql;

create function test_f() returns setof test_class_r as $$select * from test_class_r$$ language sql;

do $$ begin execute ddlx_script('test_class_r'::regclass,'{drop,nowrap}'); end $$;
