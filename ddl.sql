--
--	DDL extraction functions
--
---------------------------------------------------

SET client_min_messages = warning;

---------------------------------------------------
--	Helpers for digesting system catalogs
---------------------------------------------------

/*
CREATE TYPE pg_ddl_options AS (
  ddldrop boolean, -- DROP
  ddlcor  boolean, -- CREATE OR REPLACE 
  ddline  boolean, -- IF NOT EXISTS
  ddlwrap boolean, -- wrap in BEGIN / END
  ddldep  boolean, -- output objects which depend on this object too
  ddldata boolean  -- add statements preserve / copy data
);
*/

---------------------------------------------------

CREATE FUNCTION pg_ddl_oid_info(
  IN oid,  
  OUT name name,  OUT namespace name,  OUT kind text)
 RETURNS record
 LANGUAGE sql
AS $function$
  SELECT c.relname AS name,
         n.nspname AS namespace,
         coalesce(tt.column2,c.relkind::text) AS kind
    FROM pg_class c JOIN pg_namespace n ON (n.oid=c.relnamespace)
    left join (
       values ('r','TABLE'),
              ('v','VIEW'),
              ('i','INDEX'),
              ('S','SEQUENCE'),
              ('s','SPECIAL'),
              ('m','MATERIALIZED VIEW')
    ) as tt on tt.column1 = c.relkind
   WHERE c.oid = $1
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_get_columns(
  IN regclass,  
  OUT name name,  OUT type text,  OUT size integer,  OUT not_null boolean,  OUT "default" text, 
  OUT comment text,  OUT primary_key name,  OUT is_local boolean,  OUT attstorage text,  OUT ord smallint,  OUT namespace name, 
  OUT class_name name,  OUT sql_identifier text,  OUT nuls boolean, 
  OUT "NullF" real,  OUT "DistF" real,  OUT "DistN" numeric,  OUT regclass oid,  OUT definition text)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT a.attname AS name, format_type(t.oid, NULL::integer) AS type, 
        CASE
            WHEN (a.atttypmod - 4) > 0 THEN a.atttypmod - 4
            ELSE NULL::integer
        END AS size, a.attnotnull AS not_null, 
        def.adsrc AS "default", col_description(c.oid, a.attnum::integer) AS comment, 
        con.conname AS primary_key, 
        a.attislocal AS is_local, a.attstorage::text, a.attnum AS ord, s.nspname AS namespace, 
        c.relname AS class_name, 
        (c.oid::regclass)::text || '.' || quote_ident(a.attname) AS sql_identifier,
        CASE t.typname
            WHEN 'numeric'::name THEN false
            WHEN 'bool'::name THEN false
            ELSE true
        END AS nuls, 
         st.stanullfrac AS "NullF", 
        CASE
            WHEN st.stadistinct < 0::double precision THEN - st.stadistinct
            ELSE NULL::real
        END AS "DistF", 
        CASE
            WHEN st.stadistinct >= 0::double precision THEN st.stadistinct
            ELSE NULL::real
        END::numeric AS "DistN", 
        c.oid AS regclass, 
        (((quote_ident(a.attname::text) || ' '::text) || format_type(t.oid, NULL::integer)) || 
        CASE
            WHEN (a.atttypmod - 4) > 65536 THEN ((('('::text || (((a.atttypmod - 4) / 65536)::text)) || ','::text) || (((a.atttypmod - 4) % 65536)::text)) || ')'::text
            WHEN (a.atttypmod - 4) > 0 THEN ('('::text || ((a.atttypmod - 4)::text)) || ')'::text
            ELSE ''::text
        END) || 
        CASE
            WHEN a.attnotnull THEN ' NOT NULL'::text
            ELSE ''::text
        END AS definition
   FROM pg_class c
   JOIN pg_namespace s ON s.oid = c.relnamespace
   JOIN pg_attribute a ON c.oid = a.attrelid
   LEFT JOIN pg_attrdef def ON c.oid = def.adrelid AND a.attnum = def.adnum
   LEFT JOIN pg_constraint con ON con.conrelid = c.oid AND (a.attnum = ANY (con.conkey)) AND con.contype = 'p'::"char"
   LEFT JOIN pg_type t ON t.oid = a.atttypid
   JOIN pg_namespace tn ON tn.oid = t.typnamespace
   LEFT JOIN pg_statistic st ON st.starelid = c.oid AND st.staattnum = a.attnum
  WHERE (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", ''::"char", 'c'::"char"])) AND a.attnum > 0 
  AND NOT a.attisdropped AND has_table_privilege(c.oid, 'select'::text) AND has_schema_privilege(s.oid, 'usage'::text)
    AND c.oid = $1
  ORDER BY s.nspname, c.relname, a.attnum;
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_constraints(
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
        CASE c.contype
            WHEN 'c'::"char" THEN 'CHECK'::text
            WHEN 'f'::"char" THEN 'FOREIGN KEY'::text
            WHEN 'p'::"char" THEN 'PRIMARY KEY'::text
            WHEN 'u'::"char" THEN 'UNIQUE'::text
            ELSE NULL::text
        END AS constraint_type, pg_get_constraintdef(c.oid) AS constraint_definition, 
        c.condeferrable AS is_deferrable, 
        c.condeferred  AS initially_deferred, 
        r.oid as regclass, c.oid AS sysid
   FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r
  WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace AND c.conrelid = r.oid;
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_rules(
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
  WHERE NOT (r.ev_type = '1'::"char" AND r.rulename = '_RETURN'::name)
  ORDER BY r.oid
  $function$;
  
---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_triggers(
  OUT is_constraint text, OUT trigger_name text, OUT action_order text, 
  OUT event_manipulation text, OUT event_object_sql_identifier text, OUT action_statement text, OUT action_orientation text, 
  OUT regclass regclass, OUT procid oid, OUT regprocedure regprocedure, OUT event_object_schema text, 
  OUT event_object_table text, OUT trigger_key text)
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
        END AS action_orientation, c.oid::regclass AS regclass, p.oid AS procid, p.oid::regprocedure AS regprocedure, s.nspname::text AS event_object_schema,
         c.relname::text AS event_object_table, (quote_ident(t.tgname::text) || ' ON '::text) || c.oid::regclass::text AS trigger_key
   FROM pg_trigger t
   LEFT JOIN pg_class c ON c.oid = t.tgrelid
   LEFT JOIN pg_namespace s ON s.oid = c.relnamespace
   LEFT JOIN pg_proc p ON p.oid = t.tgfoid
   LEFT JOIN pg_namespace s1 ON s1.oid = p.pronamespace
$function$;

CREATE OR REPLACE FUNCTION pg_ddl_get_indexes(
  OUT sysid oid, OUT namespace text, OUT class text, OUT name text, OUT tablespace text, OUT indexdef text, OUT constraint_name text)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT c.oid AS sysid, n.nspname::text AS namespace, c.relname::text AS class, i.relname::text AS name, NULL::text AS tablespace, 
        CASE d.refclassid
            WHEN 'pg_constraint'::regclass THEN (((((('ALTER TABLE '::text || quote_ident(n.nspname::text)) || '.'::text) || quote_ident(c.relname::text)) || ' ADD CONSTRAINT '::text) || quote_ident(cc.conname::text)) || ' '::text) || pg_get_constraintdef(cc.oid)
            ELSE pg_get_indexdef(i.oid)
        END AS indexdef, cc.conname::text AS constraint_name
   FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_class i ON i.oid = x.indexrelid
   JOIN pg_depend d ON d.objid = x.indexrelid
   LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
   LEFT JOIN pg_constraint cc ON cc.oid = d.refobjid
  WHERE c.relkind = 'r'::"char" AND i.relkind = 'i'::"char"
  ORDER BY c.oid, n.nspname, c.relname, i.relname, NULL::text, 
CASE d.refclassid
    WHEN 'pg_constraint'::regclass THEN (((((('ALTER TABLE '::text || quote_ident(n.nspname::text)) || '.'::text) || quote_ident(c.relname::text)) || ' ADD CONSTRAINT '::text) || quote_ident(cc.conname::text)) || ' '::text) || pg_get_constraintdef(cc.oid)
    ELSE pg_get_indexdef(i.oid)
END, cc.conname
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION pg_ddl_get_functions(
  OUT sysid oid, OUT namespace name, OUT name name, OUT comment text, 
  OUT owner name, OUT sql_identifier text, OUT language name, OUT attributes text, 
  OUT retset boolean, OUT is_trigger boolean, OUT returns text, OUT arguments text, 
  OUT definition text, OUT security text, OUT is_strict text, OUT argtypes oidvector)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT p.oid AS sysid, 
        s.nspname AS namespace, 
        p.proname AS name, 
        pg_description.description AS comment, 
        u.rolname AS owner,
        p.oid::regprocedure::text AS sql_identifier, l.lanname AS language, 
        CASE p.provolatile
            WHEN 'i'::"char" THEN 'IMMUTABLE'::text
            WHEN 's'::"char" THEN 'STABLE'::text
            WHEN 'v'::"char" THEN 'VOLATILE'::text
            ELSE NULL::text
        END AS attributes, 
        p.proretset AS retset, 
        p.prorettype = 'trigger'::regtype::oid AS is_trigger, text(p.prorettype::regtype) AS returns, oidvectortypes(p.proargtypes) AS arguments, 
        p.prosrc AS definition, 
        CASE p.prosecdef
            WHEN true THEN 'DEFINER'::text
            ELSE 'INVOKER'::text
        END AS security, 
        case p.proisstrict 
            WHEN true THEN 'STRICT'::text
            ELSE NULL
        END AS is_strict, 
        p.proargtypes AS argtypes
   FROM pg_proc p
   LEFT JOIN pg_namespace s ON s.oid = p.pronamespace
   LEFT JOIN pg_language l ON l.oid = p.prolang
   LEFT JOIN pg_roles u ON p.proowner = u.oid
   LEFT JOIN pg_description ON p.oid = pg_description.objoid;
$function$;

---------------------------------------------------
--	DDL generator functions for individial object types
---------------------------------------------------

CREATE FUNCTION pg_ddl_create_table(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 SELECT 
'CREATE TABLE '||(oid::regclass::text)||E' (\n'||
  coalesce(''||(
   SELECT coalesce(string_agg('    '||definition,E',\n'),'')
     FROM pg_ddl_get_columns($1)
    WHERE regclass = $1 AND is_local
  )||E'\n','')||
  ')'||
 (SELECT 
  coalesce(' INHERITS(' || string_agg(i.inhparent::regclass::text,', ') || ')', '')
  FROM pg_inherits i
  WHERE i.inhrelid = $1) ||
 CASE relhasoids
  WHEN true THEN ' WITH OIDS'
  ELSE ''
 END 
 FROM pg_class c
 WHERE oid = $1
 AND relkind='r'
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_create_view(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 SELECT 
 'CREATE '||
  case relkind 
  when 'v' THEN 'OR REPLACE VIEW ' 
  when 'm' THEN 'MATERIALIZED VIEW '
  end || (oid::regclass::text) || E' AS\n'||
  pg_catalog.pg_get_viewdef(oid,true)||E'\n'
 FROM pg_class t
 WHERE oid = $1
 AND relkind = 'v' OR relkind = 'm'
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_create_class(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 SELECT 
'--
-- Name: '||coalesce(c.relname,'')||'; Type: '||coalesce(tt.column2,c.relkind)||'; Schema: '||n.nspname||'; Owner: '||coalesce(pg_get_userbyid(c.relowner),'')||'
--

' ||

 CASE 
  WHEN relkind in ('v','m') THEN pg_ddl_create_view($1) 
  ELSE pg_ddl_create_table($1) || E';\n' 
 END ||
  'COMMENT ON '||coalesce(tt.column2,c.relkind) || '  '  || (c.oid::regclass::text) ||
  ' IS ' || coalesce(quote_ident(obj_description(c.oid)),'NULL') || E';\n'  || 
  coalesce((select string_agg(
           'COMMENT ON COLUMN ' || (c.oid::regclass::text) || '.' || quote_ident(name) ||
           ' IS ' || coalesce(quote_literal(comment),'NULL') || E';\n', ''
         ) 
    from pg_ddl_get_columns($1) 
   where regclass = $1 
     and comment IS NOT NULL 
  ) || E'\n',
         '') 
    from pg_class c 
    join pg_namespace n on n.oid=c.relnamespace
    left join (
       values ('r','TABLE'),
              ('v','VIEW'),
              ('i','INDEX'),
              ('S','SEQUENCE'),
              ('s','SPECIAL'),
              ('m','MATERIALIZED VIEW')
    ) as tt on tt.column1 = c.relkind
  where c.oid = $1
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_alter_table_defaults(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
  select 
    coalesce(
      string_agg( 
        'ALTER TABLE '||text(regclass::regclass)|| 
          ' ALTER '||quote_ident(name)|| 
          ' SET DEFAULT '||"default", 
        E';\n') || E';\n\n', 
    '')
   from pg_ddl_get_columns($1)
  where regclass = $1 and "default" is not null
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_create_constraints(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with cs as (
  SELECT
   'ALTER TABLE ' || text(regclass(regclass)) ||  
   ' ADD CONSTRAINT ' || quote_ident(constraint_name) || 
   E'\n  ' || constraint_definition as sql
    from pg_ddl_get_constraints()
   where regclass=$1
   order by constraint_type desc, sysid
 )
 select coalesce(string_agg(sql,E';\n') || E';\n\n','')
   from cs
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_create_rules(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
  select 
    coalesce(
      string_agg(rule_definition,E'\n')||E'\n\n',
      '')
    from pg_ddl_get_rules()
   where regclass = $1
     and rule_definition is not null
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_create_triggers(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with tg as (
  select 
   'CREATE TRIGGER '||quote_ident(trigger_name)||
   ' '||action_order||' '||event_manipulation|| 
   ' ON '|| text($1) ||E'\n   FOR EACH '|| action_orientation ||  
   ' EXECUTE PROCEDURE '||action_statement AS sql 
 from pg_ddl_get_triggers() where regclass = $1 and is_constraint is null
 order by trigger_name 
 -- per SQL triggers get calles in order created vs name as in postgresql
 )
 select coalesce(string_agg(sql,E';\n')||E';\n','')
   from tg
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_create_indexes(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 SELECT coalesce( string_agg(indexdef||E';\n','') || E'\n' , '')
 FROM pg_ddl_get_indexes()
 WHERE sysid = $1
 AND constraint_name is null
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_alter_owner(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 select 
   'ALTER TABLE '||text($1)||' OWNER TO '||quote_ident(pg_get_userbyid(c.relowner))||E';\n'
   from pg_class c
  where oid = $1
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_create_function(regproc)
 RETURNS text
 LANGUAGE sql
AS $function$ 
SELECT  
'--
-- Name: '||coalesce(sql_identifier,'')||'; Type: FUNCTION; Schema: '||namespace||'; Owner: '||coalesce(owner,'')||'
--

' ||
E'CREATE OR REPLACE FUNCTION ' || sql_identifier || ' 
  RETURNS ' || 
  CASE retset
  WHEN true THEN 'SETOF ' ELSE '' END || 
  returns ||  
  coalesce(' 
  '||attributes,'') || coalesce(' 
  '||is_strict,'') || ' 
  LANGUAGE ' || quote_literal(language) || ' 
  SECURITY ' || security || ' 
  AS $ddl$'||definition|| '$ddl$; 
' || coalesce(' 
COMMENT ON FUNCTION ' || sql_identifier || '  
  IS '||quote_literal(comment)||'; 
','') || 
 E'\nALTER FUNCTION '||sql_identifier||' OWNER TO '||quote_ident(owner)||';'|| 
 E'\nREVOKE ALL ON FUNCTION '||sql_identifier||E' FROM PUBLIC;\n\n' 
AS ddl 
FROM pg_ddl_get_functions()
WHERE sysid = $1 
 
$function$;


---------------------------------------------------

CREATE FUNCTION pg_ddl_grants_on_class(regclass) 
 RETURNS text
 LANGUAGE sql
 AS $_$
 with obj as (
   select * from pg_ddl_oid_info($1)
 )
 select
   'REVOKE ALL ON '||text($1)||' FROM PUBLIC;'||E'\n'||
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
$_$;

---------------------------------------------------
--	Main script generating functions
---------------------------------------------------

CREATE FUNCTION pg_ddl_script(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
   select 
     pg_ddl_create_class($1)|| 
     pg_ddl_alter_table_defaults($1)|| 
     pg_ddl_create_constraints($1)|| 
     pg_ddl_create_rules($1) || 
     pg_ddl_create_triggers($1) ||
     pg_ddl_create_indexes($1) ||
     pg_ddl_alter_owner($1) ||
     pg_ddl_grants_on_class($1)
$function$;

---------------------------------------------------

CREATE FUNCTION pg_ddl_script(regprocedure)
 RETURNS text
 LANGUAGE sql
AS $function$
   select pg_ddl_create_function($1)
$function$;


