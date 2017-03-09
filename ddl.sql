--
--  DDL extraction functions
--
---------------------------------------------------

SET client_min_messages = warning;

---------------------------------------------------

---------------------------------------------------
--  Helpers for digesting system catalogs
---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_oid_info(
  IN oid,  
  OUT oid oid, OUT name name,  OUT namespace name,  
  OUT kind text, OUT owner name, OUT sql_kind text, OUT sql_identifier text)
 RETURNS record
 LANGUAGE sql
AS $function$
  SELECT c.oid,
         c.relname AS name,
         n.nspname AS namespace,
         coalesce(cc.column2,c.relkind::text) AS kind,
         pg_get_userbyid(c.relowner) AS owner,
         coalesce(cc.column2,c.relkind::text) AS sql_kind,
         cast($1::regclass AS text) AS sql_identifier
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    left join (
       values ('r','TABLE'),
              ('v','VIEW'),
              ('i','INDEX'),
              ('S','SEQUENCE'),
              ('s','SPECIAL'),
              ('m','MATERIALIZED VIEW'),
              ('c','TYPE'),
              ('t','TOAST'),
              ('f','FOREIGN TABLE')
    ) as cc on cc.column1 = c.relkind
   WHERE c.oid = $1
   UNION 
  SELECT p.oid,
         p.proname AS name,
         n.nspname AS namespace,
         'FUNCTION' AS kind,
         pg_get_userbyid(p.proowner) AS owner,
         'FUNCTION' AS sql_kind,
         cast($1::regprocedure AS text) AS sql_identifier
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.oid = $1
   UNION 
  SELECT t.oid,
         t.typname AS name,
         n.nspname AS namespace,
         coalesce(tt.column2,t.typtype::text) AS kind,
         pg_get_userbyid(t.typowner) AS owner,
         coalesce(tt.column3,t.typtype::text) AS sql_kind,
         format_type($1,null) AS sql_identifier
    FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    left join (
       values ('b','BASE','TYPE'),
              ('c','COMPOSITE','TYPE'),
              ('d','DOMAIN','DOMAIN'),
              ('e','ENUM','TYPE'),
              ('p','PSEUDO','TYPE'),
              ('r','RANGE','TYPE')
    ) as tt on tt.column1 = t.typtype
   WHERE t.oid = $1
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_columns(
  IN regclass,  
  OUT name name,  OUT type text,  OUT size integer,  OUT not_null boolean,  
  OUT "default" text, OUT comment text,  OUT primary_key name,  
  OUT is_local boolean,  OUT storage text,  OUT collation text, OUT ord smallint,  
  OUT namespace name, OUT class_name name,  OUT sql_identifier text, 
  OUT oid, OUT definition text)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT a.attname AS name, format_type(t.oid, NULL::integer) AS type, 
        CASE
            WHEN (a.atttypmod - 4) > 0 THEN a.atttypmod - 4
            ELSE NULL::integer
        END AS size, 
        a.attnotnull AS not_null, 
        def.adsrc AS "default", 
        col_description(c.oid, a.attnum::integer) AS comment, 
        con.conname AS primary_key, 
        a.attislocal AS is_local, 
        a.attstorage::text AS storage,
        nullif(col.collcollate::text,'') AS collation, 
        a.attnum AS ord, 
        s.nspname AS namespace, 
        c.relname AS class_name, 
        text(c.oid::regclass) || '.' || quote_ident(a.attname) AS sql_identifier,
        c.oid, 
        quote_ident(a.attname::text) || ' ' || format_type(t.oid, a.atttypmod) || 
        CASE
            WHEN length(col.collcollate) > 0 
            THEN ' COLLATE ' || quote_ident(col.collcollate::text)
            ELSE ''
        END ||
        CASE
            WHEN a.attnotnull THEN ' NOT NULL'::text
            ELSE ''::text
        END AS definition
   FROM pg_class c
   JOIN pg_namespace s ON s.oid = c.relnamespace
   JOIN pg_attribute a ON c.oid = a.attrelid
   LEFT JOIN pg_attrdef def ON c.oid = def.adrelid AND a.attnum = def.adnum
   LEFT JOIN pg_constraint con ON con.conrelid = c.oid AND (a.attnum = ANY (con.conkey)) AND con.contype = 'p'
   LEFT JOIN pg_type t ON t.oid = a.atttypid
   LEFT JOIN pg_collation col ON col.oid = a.attcollation
   JOIN pg_namespace tn ON tn.oid = t.typnamespace
  WHERE c.relkind IN ('r','v','c','f') AND a.attnum > 0 AND NOT a.attisdropped 
    AND has_table_privilege(c.oid, 'select') AND has_schema_privilege(s.oid, 'usage')
    AND c.oid = $1
  ORDER BY s.nspname, c.relname, a.attnum;
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_constraints(
 regclass default null,
 OUT namespace name, 
 OUT class_name name, 
 OUT constraint_name name, 
 OUT constraint_type text, 
 OUT constraint_definition text, 
 OUT is_deferrable boolean, 
 OUT initially_deferred boolean, 
 OUT regclass oid, 
 OUT sysid oid)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT nc.nspname AS namespace, 
        r.relname AS class_name, 
        c.conname AS constraint_name, 
        case c.contype
            when 'c'::"char" then 'CHECK'::text
            when 'f'::"char" then 'FOREIGN KEY'::text
            when 'p'::"char" then 'PRIMARY KEY'::text
            when 'u'::"char" then 'UNIQUE'::text
            when 't'::"char" then 'TRIGGER'::text
            when 'x'::"char" then 'EXCLUDE'::text
            else c.contype::text
        end,
        pg_get_constraintdef(c.oid,true) AS constraint_definition,
        c.condeferrable AS is_deferrable, 
        c.condeferred  AS initially_deferred, 
        r.oid as regclass, c.oid AS sysid
   FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r
  WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace AND c.conrelid = r.oid
    AND coalesce(r.oid=$1,true);
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_rules(
  regclass default null,
  OUT namespace text, OUT class_name text, OUT rule_name text, OUT rule_event text, OUT is_instead boolean, 
  OUT rule_definition text, OUT regclass regclass)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT n.nspname::text AS namespace, c.relname::text AS class_name, r.rulename::text AS rule_name, 
        CASE
            WHEN r.ev_type = '1'::"char" THEN 'SELECT'::text
            WHEN r.ev_type = '2'::"char" THEN 'UPDATE'::text
            WHEN r.ev_type = '3'::"char" THEN 'INSERT'::text
            WHEN r.ev_type = '4'::"char" THEN 'DELETE'::text
            ELSE 'UNKNOWN'::text
        END AS rule_event, r.is_instead, pg_get_ruledef(r.oid, true) AS rule_definition, c.oid::regclass AS regclass
   FROM pg_rewrite r
   JOIN pg_class c ON c.oid = r.ev_class
   JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE coalesce(c.oid=$1,true)
    AND NOT (r.ev_type = '1'::"char" AND r.rulename = '_RETURN'::name)
  ORDER BY r.oid
  $function$;
  
---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_triggers(
  regclass default null,
  OUT is_constraint text, OUT trigger_name text, OUT action_order text, 
  OUT event_manipulation text, OUT event_object_sql_identifier text, 
  OUT action_statement text, OUT action_orientation text, 
  OUT trigger_definition text, OUT regclass regclass, OUT regprocedure regprocedure, 
  OUT event_object_schema text, OUT event_object_table text, OUT trigger_key text)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT 
        CASE t.tgisinternal
            WHEN true THEN 'CONSTRAINT'::text
            WHEN false THEN NULL::text
            ELSE NULL::text
        END AS is_constraint, t.tgname::text AS trigger_name, 
        CASE t.tgtype::integer & 2
            WHEN 2 THEN 'BEFORE'::text
            WHEN 0 THEN 'AFTER'::text
            ELSE NULL::text
        END AS action_order, 
        CASE (t.tgtype::integer / 4) & 7
            WHEN 1 THEN 'INSERT'::text
            WHEN 2 THEN 'DELETE'::text
            WHEN 3 THEN 'INSERT OR DELETE'::text
            WHEN 4 THEN 'UPDATE'::text
            WHEN 5 THEN 'INSERT OR UPDATE'::text
            WHEN 6 THEN 'UPDATE OR DELETE'::text
            WHEN 7 THEN 'INSERT OR UPDATE OR DELETE'::text
            ELSE NULL::text
        END AS event_manipulation, 
        c.oid::regclass::text AS event_object_sql_identifier, 
        p.oid::regprocedure::text AS action_statement, 
        CASE t.tgtype::integer & 1
            WHEN 1 THEN 'ROW'::text
            ELSE 'STATEMENT'::text
        END AS action_orientation, 
        pg_get_triggerdef(t.oid,true) as trigger_definition,
        c.oid::regclass AS regclass, 
        p.oid::regprocedure AS regprocedure, 
        s.nspname::text AS event_object_schema,
        c.relname::text AS event_object_table, 
        (quote_ident(t.tgname::text) || ' ON '::text) || c.oid::regclass::text AS trigger_key
   FROM pg_trigger t
   LEFT JOIN pg_class c ON c.oid = t.tgrelid
   LEFT JOIN pg_namespace s ON s.oid = c.relnamespace
   LEFT JOIN pg_proc p ON p.oid = t.tgfoid
   LEFT JOIN pg_namespace s1 ON s1.oid = p.pronamespace
   WHERE coalesce(c.oid=$1,true)
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_indexes(
  regclass default null,
  OUT oid oid, OUT namespace text, OUT class text, OUT name text, 
  OUT tablespace text, OUT indexdef text, OUT constraint_name text)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT DISTINCT
        c.oid AS oid, 
        n.nspname::text AS namespace, 
        c.relname::text AS class, 
        i.relname::text AS name,
        NULL::text AS tablespace, 
        CASE d.refclassid
            WHEN 'pg_constraint'::regclass 
            THEN 'ALTER TABLE ' || text(c.oid::regclass) 
                 || ' ADD CONSTRAINT ' || quote_ident(cc.conname) 
                 || ' ' || pg_get_constraintdef(cc.oid)
            ELSE pg_get_indexdef(i.oid)
        END AS indexdef, 
        cc.conname::text AS constraint_name
   FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_namespace n ON n.oid = c.relnamespace
   JOIN pg_class i ON i.oid = x.indexrelid
   JOIN pg_depend d ON d.objid = x.indexrelid
   LEFT JOIN pg_constraint cc ON cc.oid = d.refobjid
  WHERE c.relkind in ('r','m') AND i.relkind = 'i'::"char" 
    AND coalesce(c.oid = $1,true)
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_functions(
  regproc default null,
  OUT sysid oid, OUT namespace name, OUT name name, OUT comment text, 
  OUT owner name, OUT sql_identifier text, OUT language name, OUT attributes text, 
  OUT retset boolean, OUT is_trigger boolean, OUT returns text, OUT arguments text, 
  OUT definition text, OUT security text, OUT is_strict text, OUT argtypes oidvector,
  OUT cost real, OUT rows real)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT p.oid AS sysid, 
        s.nspname AS namespace, 
        p.proname AS name, 
        pg_description.description AS comment, 
        u.rolname AS owner,
        p.oid::regprocedure::text AS sql_identifier, 
        l.lanname AS language, 
        CASE p.provolatile
            WHEN 'i'::"char" THEN 'IMMUTABLE'::text
            WHEN 's'::"char" THEN 'STABLE'::text
            WHEN 'v'::"char" THEN 'VOLATILE'::text
            ELSE NULL::text
        END AS attributes, 
        p.proretset AS retset, 
        p.prorettype = 'trigger'::regtype::oid AS is_trigger, 
        text(p.prorettype::regtype) AS returns, 
        pg_get_function_arguments(p.oid) AS arguments, 
--        oidvectortypes(p.proargtypes) AS argtypes, 
        p.prosrc AS definition, 
        CASE p.prosecdef
            WHEN true THEN 'DEFINER'::text
            ELSE 'INVOKER'::text
        END AS security, 
        case p.proisstrict 
            WHEN true THEN 'STRICT'::text
            ELSE NULL
        END AS is_strict, 
        p.proargtypes AS proargtypes,
        p.procost as cost,
        p.prorows as rows
   FROM pg_proc p
   LEFT JOIN pg_namespace s ON s.oid = p.pronamespace
   LEFT JOIN pg_language l ON l.oid = p.prolang
   LEFT JOIN pg_roles u ON p.proowner = u.oid
   LEFT JOIN pg_description ON p.oid = pg_description.objoid
   WHERE coalesce(p.oid = $1, true)
$function$;

---------------------------------------------------
--  DDL generator functions for individial object types
---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_banner(name text, kind text, namespace text, owner text)
 RETURNS text
 LANGUAGE sql
AS $function$
  SELECT 
'--
-- Name: '||$1||'; Type: '||$2||'; Schema: '||$3||'; Owner: '||$4||'
--

'
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_comment(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from pg_ddl_oid_info($1))
 select
  'COMMENT ON ' || obj.sql_kind
   || ' '  || sql_identifier ||
  ' IS ' || quote_nullable(obj_description(oid)) || E';\n'
   from obj
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_table(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
  with obj as (select * from pg_ddl_oid_info($1))
  select 
    'CREATE '||
  case relpersistence
    when 'u' then 'UNLOGGED '
    when 't' then 'TEMPORARY '
    else ''
  end
  || obj.kind || ' ' 
  || obj.sql_identifier
  || case obj.kind when 'TYPE' then ' AS' else '' end 
  ||
  E' (\n'||
    coalesce(''||(
      SELECT coalesce(string_agg('    '||definition,E',\n'),'')
        FROM pg_ddl_get_columns($1) WHERE is_local
    )||E'\n','')||')'
  ||
  (SELECT 
    coalesce(' INHERITS(' || string_agg(i.inhparent::regclass::text,', ') || ')', '')
     FROM pg_inherits i WHERE i.inhrelid = $1) 
  ||
  CASE relhasoids WHEN true THEN ' WITH OIDS' ELSE '' END 
  ||
  coalesce(
    E'\nSERVER '||quote_ident(fs.srvname)||E'\nOPTIONS (\n'||
    (select string_agg('    '||quote_ident(option_name)||' '||quote_nullable(option_value),E',\n')
       from pg_options_to_table(ft.ftoptions))||E'\n)'
    ,'') 
  ||
  E';\n'
 FROM pg_class c JOIN obj ON (true)
 LEFT JOIN pg_foreign_table  ft ON (c.oid = ft.ftrelid)
 LEFT JOIN pg_foreign_server fs ON (ft.ftserver = fs.oid)
 WHERE c.oid = $1
-- AND relkind in ('r','c')
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_view(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 select 
 'CREATE '||
  case relkind 
    when 'v' THEN 'OR REPLACE VIEW ' 
    when 'm' THEN 'MATERIALIZED VIEW '
  end || (oid::regclass::text) || E' AS\n'||
  pg_catalog.pg_get_viewdef(oid,true)||E'\n'
 FROM pg_class t
 WHERE oid = $1
   AND relkind in ('v','m')
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_sequence(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from pg_ddl_oid_info($1))
 select 
 'CREATE SEQUENCE '||(oid::regclass::text) || E';\n'
 ||'ALTER SEQUENCE '||(oid::regclass::text) 
 ||E'\n INCREMENT BY '||increment
 ||E'\n MINVALUE '||minimum_value
 ||E'\n MAXVALUE '||maximum_value
 ||E'\n START WITH '||start_value
 ||E'\n '|| case cycle_option when 'YES' then 'CYCLE' else 'NO CYCLE' end
 ||E';\n'
 FROM information_schema.sequences s JOIN obj ON (true)
 WHERE sequence_schema = obj.namespace
   AND sequence_name = obj.name
   AND obj.kind = 'SEQUENCE'
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_type_base(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$
select 'CREATE TYPE ' || format_type($1,null) || ' (' || E'\n ' 
       || E' INPUT = '  || cast(t.typinput::regproc as text)  
       || E',\n  OUTPUT = ' || cast(t.typoutput::regproc as text)  
       || coalesce(E',\n  SEND = ' || nullif(cast(t.typsend::regproc as text),'-'),'') 
       || coalesce(E',\n  RECEIVE = ' || nullif(cast(t.typreceive::regproc as text),'-'),'')
       || coalesce(E',\n  TYPMOD_IN = ' || nullif(cast(t.typmodin::regproc as text),'-'),'')
       || coalesce(E',\n  TYPMOD_OUT = ' || nullif(cast(t.typmodout::regproc as text),'-'),'')
       || coalesce(E',\n  ANALYZE = ' || nullif(cast(t.typanalyze::regproc as text),'-'),'')
       || E',\n  INTERNALLENGTH = ' || case when t.typlen < 0 then 'VARIABLE' else cast(t.typlen as text) end
       || case when t.typbyval then E',\n  PASSEDBYVALUE' else '' end
       || E',\n  ALIGNMENT = ' || 
		case t.typalign
			when 'c' then 'char'
			when 's' then 'int2'
			when 'i' then 'int4'
			when 'd' then 'double'
		end 
       || E',\n  STORAGE = ' || 
		case t.typstorage
			when 'p' then 'plain'
			when 'e' then 'external'
			when 'm' then 'main'
			when 'x' then 'extended'
		end 
       || E',\n  CATEGORY = ' || quote_nullable(t.typcategory)  
       || case when t.typispreferred then E',\n  PREFERRED = true' else '' end
       || case when t.typdefault is not null then E',\n  DEFAULT = ' || quote_nullable(t.typdefault)
          else '' end
       || case when t.typelem <> 0 then E',\n  ELEMENT = ' || format_type(t.typelem,null)
          else '' end
       || E',\n  DELIMITER = ' || quote_nullable(t.typdelim)  
       || E',\n  COLLATABLE = ' || 
          case when t.typcollation <> 0 then 'true' else 'false' end
       || E'\n);\n\n'
  from pg_type t
 where oid = $1
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_type_enum(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$
with
ee as (
 select 
   quote_nullable(enumlabel) as label
   from pg_enum
  where enumtypid = $1
  order by enumsortorder
)
select 'CREATE TYPE ' || format_type($1,null) || ' AS ENUM (' || E'\n ' ||
       string_agg(label,E'\n ') || E'\n);\n\n'
  from ee
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_type_domain(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$
with
cc as (
  select pg_get_constraintdef(oid) as definition
    from pg_constraint con
   where con.contypid = $1
   order by oid
)
select 'CREATE DOMAIN ' || format_type(t.oid,null) 
       || E'\n AS ' || format_type(t.typbasetype,typtypmod) 
       || coalesce(E'\n '||(SELECT string_agg(definition,E'\n ') FROM cc),'')
       || coalesce(E'\n DEFAULT ' || t.typdefault, '')
       || E';\n\n'
  from pg_type t
 where oid = $1
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_index(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with ii as (
 SELECT CASE d.refclassid
            WHEN 'pg_constraint'::regclass 
            THEN 'ALTER TABLE ' || text(c.oid::regclass) 
                 || ' ADD CONSTRAINT ' || quote_ident(cc.conname) 
                 || ' ' || pg_get_constraintdef(cc.oid)
            ELSE pg_get_indexdef(i.oid)
        END AS indexdef 
   FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_class i ON i.oid = x.indexrelid
   JOIN pg_depend d ON d.objid = x.indexrelid
   LEFT JOIN pg_constraint cc ON cc.oid = d.refobjid
  WHERE c.relkind in ('r','m') AND i.relkind = 'i'::"char" 
    AND i.oid = $1
)
 SELECT indexdef || E';\n'
   FROM ii
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_class(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from pg_ddl_oid_info($1)),

 comments as (
   select 'COMMENT ON COLUMN ' || text($1) || '.' || quote_ident(name) ||
          ' IS ' || quote_nullable(comment) || ';' as cc
     from pg_ddl_get_columns($1) 
    where comment IS NOT NULL 
 ),

 settings as (
   select 'ALTER ' || obj.kind || ' ' || text($1) || ' SET (' || 
          quote_ident(option_name)||'='||quote_nullable(option_value) ||');' as ss
     from pg_options_to_table((select reloptions from pg_class where oid = $1))
     join obj on (true)
 )

 select pg_ddl_banner(obj.name,obj.kind,obj.namespace,obj.owner) 
  ||
 case 
  when obj.kind in ('VIEW','MATERIALIZED VIEW') then pg_ddl_create_view($1)  
  when obj.kind in ('TABLE','TYPE','FOREIGN TABLE') then pg_ddl_create_table($1)
  when obj.kind in ('SEQUENCE') then pg_ddl_create_sequence($1)
  when obj.kind in ('INDEX') then pg_ddl_create_index($1)
  else '-- UNSUPPORTED CLASS: '||obj.kind
 end 
  || E'\n' ||
  case when obj.kind not in ('TYPE') then pg_ddl_comment($1) else '' end
  ||
  coalesce((select string_agg(cc,E'\n')||E'\n' from comments),'')
  ||
  coalesce(E'\n'||(select string_agg(ss,E'\n')||E'\n' from settings),'') 
  || E'\n'
    from obj
    
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_alter_table_defaults(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
  select 
    coalesce(
      string_agg( 
        'ALTER TABLE '||text($1)|| 
          ' ALTER '||quote_ident(name)|| 
          ' SET DEFAULT '||"default", 
        E';\n') || E';\n\n', 
    '')
   from pg_ddl_get_columns($1)
  where "default" is not null
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_constraints(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with cs as (
  SELECT
   'ALTER TABLE ' || text(regclass(regclass)) ||  
   ' ADD CONSTRAINT ' || quote_ident(constraint_name) || 
   E'\n  ' || constraint_definition as sql
    from pg_ddl_get_constraints($1)
   order by constraint_type desc, sysid
 )
 select coalesce(string_agg(sql,E';\n') || E';\n\n','')
   from cs
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_rules(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
  select coalesce(string_agg(rule_definition,E'\n')||E'\n\n','')
    from pg_ddl_get_rules()
   where regclass = $1
     and rule_definition is not null
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_triggers(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with tg as (
  select trigger_definition as sql 
 from pg_ddl_get_triggers($1) where is_constraint is null
 order by trigger_name 
 -- per SQL triggers get called in order created vs name as in PostgreSQL
 )
 select coalesce(string_agg(sql,E';\n')||E';\n\n','')
   from tg
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_indexes(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with ii as (select * from pg_ddl_get_indexes($1) order by name)
 SELECT coalesce( string_agg(indexdef||E';\n','') || E'\n' , '')
   FROM ii
  WHERE constraint_name is null
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_alter_owner(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from pg_ddl_oid_info($1))
 select
   case
     when obj.kind = 'INDEX' then ''
     else 'ALTER '||sql_kind||' '||sql_identifier||' OWNER TO '||quote_ident(owner)||E';\n'
   end
  from obj 
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_create_function(regproc)
 RETURNS text
 LANGUAGE sql
AS $function$ 
 with obj as (select * from pg_ddl_oid_info($1))
 select
  pg_ddl_banner(sql_identifier,'FUNCTION',namespace,owner) ||
  trim(trailing E'\n' from pg_get_functiondef($1)) || E';\n\n' ||
  pg_ddl_comment($1) || E'\n'
   from obj
$function$  strict;


---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_grants_on_class(regclass) 
 RETURNS text
 LANGUAGE sql
 AS $function$
 with obj as (select * from pg_ddl_oid_info($1))
 select
   coalesce(
    string_agg ('GRANT '||privilege_type|| 
                ' ON '||text($1)||' TO '|| 
                CASE grantee  
                 WHEN 'PUBLIC' THEN 'PUBLIC' 
                 ELSE quote_ident(grantee) 
                END || 
                CASE is_grantable  
                 WHEN 'YES' THEN ' WITH GRANT OPTION' 
                 ELSE '' 
                END || 
                E';\n', ''),
    '')
 FROM information_schema.table_privileges g 
 join obj on (true)
 WHERE table_schema=obj.namespace 
   AND table_name=obj.name
   AND grantee<>obj.owner
$function$  strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_grants_on_proc(regproc) 
 RETURNS text
 LANGUAGE sql
 AS $function$
 with obj as (select * from pg_ddl_oid_info($1))
 select
   'REVOKE ALL ON FUNCTION '||text($1::regprocedure)||' FROM PUBLIC;'||E'\n'||
   coalesce(
    string_agg ('GRANT '||privilege_type|| 
                ' ON FUNCTION '||text($1::regprocedure)||' TO '|| 
                CASE grantee  
                 WHEN 'PUBLIC' THEN 'PUBLIC' 
                 ELSE quote_ident(grantee) 
                END || 
                CASE is_grantable  
                 WHEN 'YES' THEN ' WITH GRANT OPTION' 
                 ELSE '' 
                END || 
                E';\n', ''),
    '')
 FROM information_schema.routine_privileges g 
 join obj on (true)
 WHERE routine_schema=obj.namespace 
   AND specific_name=obj.name||'_'||obj.oid
$function$  strict;

---------------------------------------------------
--  Main script generating functions
---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_script(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$ select null::text $function$;
-- will be defined later

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_script(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
   select 
     pg_ddl_create_class($1) 
     || pg_ddl_alter_table_defaults($1) 
     || pg_ddl_create_constraints($1) 
     || pg_ddl_create_indexes($1) 
     || pg_ddl_create_triggers($1) 
     || pg_ddl_create_rules($1) 
     || pg_ddl_alter_owner($1) 
     || pg_ddl_grants_on_class($1)
    from pg_class c
   where c.oid = $1 and c.relkind <> 'c'
   union 
  select pg_ddl_script(t.oid::regtype)
    from pg_class c
    left join pg_type t on (c.oid=t.typrelid)
   where c.oid = $1 and c.relkind = 'c'

$function$  strict;

COMMENT ON FUNCTION pg_ddl_script(regclass) IS 'Get SQL definition for a table, view, sequence or index';


---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_script(regprocedure)
 RETURNS text
 LANGUAGE sql
AS $function$
   select 
     pg_ddl_create_function($1) 
     || pg_ddl_alter_owner($1) 
     || pg_ddl_grants_on_proc($1)
$function$  strict;

COMMENT ON FUNCTION pg_ddl_script(regprocedure) IS 'Get SQL definition for a function/procedure';

CREATE OR REPLACE FUNCTION pg_ddl_script(regproc)
 RETURNS text
 LANGUAGE sql
AS $$ select pg_ddl_script($1::regprocedure) $$;

COMMENT ON FUNCTION pg_ddl_script(regproc) IS 'Get SQL definition for a function/procedure';

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_script(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$
   select pg_ddl_create_class(c.oid::regclass) -- type
          || pg_ddl_comment(t.oid)
          || pg_ddl_alter_owner(t.oid) 
     from pg_type t
     join pg_class c on (c.oid=t.typrelid)
    where t.oid = $1 and t.typtype = 'c' and c.relkind = 'c'
    union
   select pg_ddl_script(c.oid::regclass) -- table, etc
     from pg_type t
     join pg_class c on (c.oid=t.typrelid)
    where t.oid = $1 and t.typtype = 'c' and c.relkind <> 'c'
    union
   select case t.typtype
            when 'e' then pg_ddl_create_type_enum(t.oid)
            when 'd' then pg_ddl_create_type_domain(t.oid)
            when 'b' then pg_ddl_create_type_base(t.oid)
		    else '-- UNSUPPORTED TYPE: ' || t.typtype
		  end 
          || pg_ddl_comment(t.oid)
          || pg_ddl_alter_owner(t.oid) 
     from pg_type t
    where t.oid = $1 
$function$  strict;

COMMENT ON FUNCTION pg_ddl_script(regtype) IS 'Get SQL definition for user defined data type';
