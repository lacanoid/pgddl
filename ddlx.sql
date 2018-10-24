--
-- DDL eXtraction functions
-- version 0.9 lacanoid@ljudmila.org
--
---------------------------------------------------

SET client_min_messages = warning;

---------------------------------------------------

---------------------------------------------------
-- Helpers for digesting system catalogs
---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_identify(
  IN oid,
  OUT oid oid, OUT classid regclass,
  OUT name name, OUT namespace name,
  OUT kind text, OUT owner name, OUT sql_kind text,
  OUT sql_identifier text)
 RETURNS record
 LANGUAGE sql
AS $function$
  WITH
  rel_kind(k,v) AS (
         VALUES ('r','TABLE'),
                ('v','VIEW'),
                ('i','INDEX'),
                ('S','SEQUENCE'),
                ('s','SPECIAL'),
                ('m','MATERIALIZED VIEW'),
                ('c','TYPE'),
                ('t','TOAST'),
                ('f','FOREIGN TABLE')
  ),
  typ_type(k,v,v2) AS (
         VALUES ('b','BASE','TYPE'),
                ('c','COMPOSITE','TYPE'),
                ('d','DOMAIN','DOMAIN'),
                ('e','ENUM','TYPE'),
                ('p','PSEUDO','TYPE'),
                ('r','RANGE','TYPE')
  )
  SELECT c.oid,
         'pg_class'::regclass,
         c.relname AS name,
         n.nspname AS namespace,
         coalesce(cc.v,c.relkind::text) AS kind,
         pg_get_userbyid(c.relowner) AS owner,
         coalesce(cc.v,c.relkind::text) AS sql_kind,
         cast($1::regclass AS text) AS sql_identifier
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN rel_kind AS cc on cc.k = c.relkind
   WHERE c.oid = $1
   UNION
  SELECT p.oid,
         'pg_proc'::regclass,
         p.proname AS name,
         n.nspname AS namespace,
         'FUNCTION' AS kind,
         pg_get_userbyid(p.proowner) AS owner,
         case
           when p.proisagg then 'AGGREGATE'
           else 'FUNCTION'
         end AS sql_kind,
         cast($1::regprocedure AS text) AS sql_identifier
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.oid = $1
   UNION
  SELECT t.oid,
         'pg_type'::regclass,
         t.typname AS name,
         n.nspname AS namespace,
         coalesce(tt.v,t.typtype::text) AS kind,
         pg_get_userbyid(t.typowner) AS owner,
         coalesce(cc.v,tt.v2,t.typtype::text) AS sql_kind,
         format_type($1,null) AS sql_identifier
    FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    LEFT JOIN typ_type AS tt ON tt.k = t.typtype
    LEFT JOIN pg_class AS c ON c.oid = t.typrelid
    LEFT JOIN rel_kind AS cc ON cc.k = c.relkind
   WHERE t.oid = $1
   UNION
  SELECT r.oid,
         'pg_roles'::regclass,
         r.rolname as name,
         null as namespace,
         case when rolcanlogin then 'USER' else 'GROUP' end as kind,
         null as owner,
         'ROLE' as sql_kind,
         quote_ident(r.rolname) as sql_identifier
    FROM pg_roles r
   WHERE r.oid = $1
   UNION
  SELECT n.oid,
         'pg_namespace'::regclass,
         n.nspname as name,
         current_database() as namespace,
         case
           when n.nspname like 'pg_%' then 'SYSTEM'
           when n.nspname = r.rolname then 'AUTHORIZATION'
           else 'NAMESPACE'
         end as kind,
         pg_get_userbyid(n.nspowner) AS owner,
         'SCHEMA' as sql_kind,
         quote_ident(n.nspname) as sql_identifier
    FROM pg_namespace n join pg_roles r on r.oid = n.nspowner
   WHERE n.oid = $1
   UNION
  SELECT con.oid,
         'pg_constraint'::regclass,
         con.conname as name,
         c.relname as namespace,
         coalesce(tt.column2,con.contype) as kind,
         null as owner,
         'CONSTRAINT' as sql_kind,
         quote_ident(con.conname)
         ||coalesce(' ON '||cast(c.oid::regclass as text),'') as sql_identifier
    FROM pg_constraint con
    left JOIN pg_class c ON (con.conrelid=c.oid)
    LEFT join (
         values ('f','FOREIGN KEY'),
                ('c','CHECK'),
                ('x','EXCLUDE'),
                ('u','UNIQUE'),
                ('p','PRIMARY KEY'),
                ('t','TRIGGER')
         ) as tt on tt.column1 = con.contype
   WHERE con.oid = $1
   UNION
  SELECT t.oid,
         'pg_trigger'::regclass,
         t.tgname as name,
         c.relname as namespace,
      CASE t.tgtype::integer & 2
            WHEN 2 THEN 'BEFORE'::text
            WHEN 0 THEN 'AFTER'::text
            ELSE NULL::text
         END AS kind,
         null as owner,
         'TRIGGER' as sql_kind,
         format('%I ON %s',t.tgname,cast(c.oid::regclass as text)) as sql_identifier
    FROM pg_trigger t join pg_class c on (t.tgrelid=c.oid)
   WHERE t.oid = $1
   UNION
  SELECT ad.oid,
         'pg_attrdef'::regclass,
         a.attname as name,
         c.relname as namespace,
         'DEFAULT' as kind,
         null as owner,
         'DEFAULT' as sql_kind,
         format('%s.%I',cast(c.oid::regclass as text),a.attname) as sql_identifier
    FROM pg_attrdef ad
    JOIN pg_class c ON (ad.adrelid=c.oid)
    JOIN pg_attribute a ON (c.oid = a.attrelid and a.attnum=ad.adnum)
   WHERE ad.oid = $1
   UNION
  SELECT op.oid,
         'pg_operator'::regclass,
         op.oprname as name,
         n.nspname as namespace,
         'OPERATOR' as kind,
         pg_get_userbyid(op.oprowner) as owner,
         'OPERATOR' as sql_kind,
         cast(op.oid::regoperator as text) as sql_identifier
    FROM pg_operator op JOIN pg_namespace n ON n.oid=op.oprnamespace
   WHERE op.oid = $1
   UNION
  SELECT cfg.oid,
         'pg_ts_config'::regclass,
         cfg.cfgname as name,
         n.nspname as namespace,
         'TEXT SEARCH CONFIGURATION' as kind,
         pg_get_userbyid(cfg.cfgowner) as owner,
         'TEXT SEARCH CONFIGURATION' as sql_kind,
         cast(cfg.oid::regconfig as text) as sql_identifier
    FROM pg_ts_config cfg JOIN pg_namespace n ON n.oid=cfg.cfgnamespace
   WHERE cfg.oid = $1
   UNION
  SELECT dict.oid,
         'pg_ts_dict'::regclass,
         dict.dictname as name,
         n.nspname as namespace,
         'TEXT SEARCH DICTIONARY' as kind,
         pg_get_userbyid(dict.dictowner) as owner,
         'TEXT SEARCH DICTIONARY' as sql_kind,
         cast(dict.oid::regdictionary as text) as sql_identifier
    FROM pg_ts_dict dict JOIN pg_namespace n ON n.oid=dict.dictnamespace
   WHERE dict.oid = $1
   UNION
  SELECT prs.oid,
         'pg_ts_parser'::regclass,
         prs.prsname as name,
         n.nspname as namespace,
         'TEXT SEARCH PARSER' as kind,
         null as owner,
         'TEXT SEARCH PARSER' as sql_kind,
         format('%s%I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',prs.prsname) as sql_identifier
    FROM pg_ts_parser prs JOIN pg_namespace n ON n.oid=prs.prsnamespace
   WHERE prs.oid = $1
   UNION
  SELECT tmpl.oid,
         'pg_ts_template'::regclass,
         tmpl.tmplname as name,
         n.nspname as namespace,
         'TEXT SEARCH TEMPLATE' as kind,
         null as owner,
         'TEXT SEARCH TEMPLATE' as sql_kind,
         format('%s%I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',tmpl.tmplname) as sql_identifier
    FROM pg_ts_template tmpl JOIN pg_namespace n ON n.oid=tmpl.tmplnamespace
   WHERE tmpl.oid = $1
   UNION
  SELECT evt.oid,
         'pg_event_trigger'::regclass,
         evt.evtname as name,
         null as namespace,
         evt.evtevent as kind,
         pg_get_userbyid(evt.evtowner) as owner,
         'EVENT TRIGGER' as sql_kind,
         quote_ident(evt.evtname) as sql_identifier
    FROM pg_event_trigger evt
   WHERE evt.oid = $1
   UNION
  SELECT fdw.oid,
         'pg_foreign_data_wrapper'::regclass,
         fdw.fdwname as name,
         null as namespace,
         'FOREIGN DATA WRAPPER' as kind,
         pg_get_userbyid(fdw.fdwowner) as owner,
         'FOREIGN DATA WRAPPER' as sql_kind,
         quote_ident(fdw.fdwname) as sql_identifier
    FROM pg_foreign_data_wrapper fdw
   WHERE fdw.oid = $1
   UNION
  SELECT srv.oid,
         'pg_foreign_server'::regclass,
         srv.srvname as name,
         null as namespace,
         'SERVER' as kind,
         pg_get_userbyid(srv.srvowner) as owner,
         'SERVER' as sql_kind,
         quote_ident(srv.srvname) as sql_identifier
    FROM pg_foreign_server srv
   WHERE srv.oid = $1
   UNION
  SELECT ums.umid,
         'pg_user_mapping'::regclass,
         null as name,
         null as namespace,
         'USER MAPPING' as kind,
         null as owner,
         'USER MAPPING' as sql_kind,
         'FOR '||quote_ident(ums.usename)||
         ' SERVER '||quote_ident(ums.srvname) as sql_identifier
    FROM pg_user_mappings ums
   WHERE ums.umid = $1
   UNION
  SELECT ca.oid,
         'pg_cast'::regclass,
         null as name,
         null as namespace,
         'CAST' as kind,
         null as owner,
         'CAST' as sql_kind,
         format('(%s AS %s)',
           format_type(ca.castsource,null),format_type(ca.casttarget,null))
           as sql_identifier
    FROM pg_cast ca
   WHERE ca.oid = $1
   UNION
  SELECT co.oid,
         'pg_collation'::regclass,
         co.collname as name,
         n.nspname as namespace,
         'COLLATION' as kind,
         pg_get_userbyid(co.collowner) as owner,
         'COLLATION' as sql_kind,
         format('%s%I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',co.collname) as sql_identifier
    FROM pg_collation co JOIN pg_namespace n ON n.oid=co.collnamespace
   WHERE co.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_describe(
  IN regclass,
  OUT name name, OUT type text, OUT size integer, OUT not_null boolean,
  OUT "default" text, OUT comment text, OUT primary_key name,
  OUT is_local boolean, OUT storage text, OUT collation text, OUT ord smallint,
  OUT namespace name, OUT class_name name, OUT sql_identifier text,
  OUT oid, OUT definition text)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
WITH
  storage(k,v) AS (
         VALUES ('p','plain'),
                ('e','external'),
                ('m','main'),
                ('x','extended')
)
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
        storage.v AS storage,
        nullif(col.collcollate::text,'') AS collation,
        a.attnum AS ord,
        s.nspname AS namespace,
        c.relname AS class_name,
        format('%s.%I',text(c.oid::regclass),a.attname) AS sql_identifier,
        c.oid,
        format('%I %s%s%s',
         a.attname::text,
         format_type(t.oid, a.atttypmod),
         CASE
           WHEN length(col.collcollate) > 0
           THEN ' COLLATE ' || quote_ident(col.collcollate::text)
              ELSE ''
         END,
         CASE
              WHEN a.attnotnull THEN ' NOT NULL'::text
              ELSE ''::text
         END)
        AS definition
   FROM pg_class c
   JOIN pg_namespace s ON s.oid = c.relnamespace
   JOIN pg_attribute a ON c.oid = a.attrelid
   LEFT JOIN pg_attrdef def ON c.oid = def.adrelid AND a.attnum = def.adnum
   LEFT JOIN pg_constraint con
        ON con.conrelid = c.oid AND (a.attnum = ANY (con.conkey)) AND con.contype = 'p'
   LEFT JOIN pg_type t ON t.oid = a.atttypid
   LEFT JOIN pg_collation col ON col.oid = a.attcollation
   JOIN pg_namespace tn ON tn.oid = t.typnamespace
   JOIN storage on storage.k = a.attstorage
  WHERE c.relkind IN ('r','v','c','f') AND a.attnum > 0 AND NOT a.attisdropped
    AND has_table_privilege(c.oid, 'select') AND has_schema_privilege(s.oid, 'usage')
    AND c.oid = $1
  ORDER BY s.nspname, c.relname, a.attnum;
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_get_constraints(
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
        c.condeferred AS initially_deferred,
        r.oid as regclass, c.oid AS sysid
   FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r
  WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace AND c.conrelid = r.oid
    AND coalesce(r.oid=$1,true);
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_get_rules(
  regclass default null,
  OUT namespace text, OUT class_name text, OUT rule_name text, OUT rule_event text,
  OUT is_instead boolean, OUT rule_definition text, OUT regclass regclass)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT n.nspname::text AS namespace,
        c.relname::text AS class_name,
        r.rulename::text AS rule_name,
        CASE
            WHEN r.ev_type = '1'::"char" THEN 'SELECT'::text
            WHEN r.ev_type = '2'::"char" THEN 'UPDATE'::text
            WHEN r.ev_type = '3'::"char" THEN 'INSERT'::text
            WHEN r.ev_type = '4'::"char" THEN 'DELETE'::text
            ELSE 'UNKNOWN'::text
        END AS rule_event,
        r.is_instead,
        pg_get_ruledef(r.oid, true) AS rule_definition,
        c.oid::regclass AS regclass
   FROM pg_rewrite r
   JOIN pg_class c ON c.oid = r.ev_class
   JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE coalesce(c.oid=$1,true)
    AND NOT (r.ev_type = '1'::"char" AND r.rulename = '_RETURN'::name)
  ORDER BY r.oid
  $function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_get_triggers(
  regclass default null,
  OUT is_constraint text, OUT trigger_name text, OUT action_order text,
  OUT event_manipulation text, OUT event_object_sql_identifier text,
  OUT action_statement text, OUT action_orientation text,
  OUT trigger_definition text, OUT regclass regclass, OUT regprocedure regprocedure,
  OUT event_object_schema text, OUT event_object_table text, OUT sql_identifier text)
 RETURNS SETOF record
 LANGUAGE sql
AS $function$
 SELECT
        CASE t.tgisinternal
            WHEN true THEN 'CONSTRAINT'::text
            ELSE NULL::text
        END AS is_constraint, t.tgname::text AS trigger_name,
        CASE (t.tgtype::integer & 64) <> 0
            WHEN true THEN 'INSTEAD'::text
            ELSE CASE t.tgtype::integer & 2
              WHEN 2 THEN 'BEFORE'::text
              WHEN 0 THEN 'AFTER'::text
              ELSE NULL::text
            END
        END AS action_order,
        array_to_string(array[
          case when (t.tgtype::integer & 4) <> 0 then 'INSERT' end,
          case when (t.tgtype::integer & 8) <> 0 then 'DELETE' end,
          case when (t.tgtype::integer & 16) <> 0 then 'UPDATE' end,
          case when (t.tgtype::integer & 32) <> 0 then 'TRUNCATE' end
        ],' OR ') AS event_manipulation,
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
        (quote_ident(t.tgname::text) || ' ON ') || c.oid::regclass::text AS sql_identifier
   FROM pg_trigger t
   LEFT JOIN pg_class c ON c.oid = t.tgrelid
   LEFT JOIN pg_namespace s ON s.oid = c.relnamespace
   LEFT JOIN pg_proc p ON p.oid = t.tgfoid
   LEFT JOIN pg_namespace s1 ON s1.oid = p.pronamespace
   WHERE coalesce(c.oid=$1,true)
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_get_indexes(
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

CREATE OR REPLACE FUNCTION ddlx_get_functions(
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
-- oidvectortypes(p.proargtypes) AS argtypes,
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
-- DDL generator functions for individial object types
---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_banner(
   name text, kind text, namespace text, owner text, extra text default null
 )
 RETURNS text
 LANGUAGE sql
AS $function$
  SELECT format(E'%s-- Type: %s ; Name: %s; Owner: %s\n\n',
                E'--\n-- ' || extra || E'\n',
                $2,$1,$4)
$function$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_comment(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from ddlx_identify($1))
 select format(
          E'COMMENT ON %s %s IS %L;\n',
          obj.sql_kind, sql_identifier, obj_description(oid))
   from obj
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_table(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
  with obj as (select * from ddlx_identify($1))
  select
    'CREATE '||
  case relpersistence
    when 'u' then 'UNLOGGED '
    when 't' then 'TEMPORARY '
    else ''
  end
  || obj.kind || ' ' || obj.sql_identifier
  || case obj.kind when 'TYPE' then ' AS' else '' end
  ||
  E' (\n'||
    coalesce(''||(
      SELECT coalesce(string_agg('    '||definition,E',\n'),'')
        FROM ddlx_describe($1) WHERE is_local
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
    (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value),
              E',\n')
       from pg_options_to_table(ft.ftoptions))||E'\n)'
    ,'')
  ||
  E';\n'
 FROM pg_class c JOIN obj ON (true)
 LEFT JOIN pg_foreign_table ft ON (c.oid = ft.ftrelid)
 LEFT JOIN pg_foreign_server fs ON (ft.ftserver = fs.oid)
 WHERE c.oid = $1
-- AND relkind in ('r','c')
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_view(regclass)
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
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_sequence(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from ddlx_identify($1))
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
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_type_base(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$
select 'CREATE TYPE ' || format_type($1,null) || ' (' || E'\n  ' ||
       array_to_string(array[
         'INPUT = ' || cast(t.typinput::regproc as text),
         'OUTPUT = ' || cast(t.typoutput::regproc as text),
         'SEND = ' || nullif(cast(t.typsend::regproc as text),'-'),
         'RECEIVE = ' || nullif(cast(t.typreceive::regproc as text),'-'),
         'TYPMOD_IN = ' || nullif(cast(t.typmodin::regproc as text),'-'),
         'TYPMOD_OUT = ' || nullif(cast(t.typmodout::regproc as text),'-'),
         'ANALYZE = ' || nullif(cast(t.typanalyze::regproc as text),'-'),
         'INTERNALLENGTH = ' ||
            case when t.typlen < 0 then 'VARIABLE' else cast(t.typlen as text) end,
         case when t.typbyval then 'PASSEDBYVALUE' end,
         'ALIGNMENT = ' ||
      case t.typalign
   when 'c' then 'char'
   when 's' then 'int2'
   when 'i' then 'int4'
   when 'd' then 'double'
      end,
         'STORAGE = ' ||
      case t.typstorage
   when 'p' then 'plain'
   when 'e' then 'external'
   when 'm' then 'main'
   when 'x' then 'extended'
      end,
         'CATEGORY = ' || quote_nullable(t.typcategory),
         case when t.typispreferred then E'PREFERRED = true' end,
         case
           when t.typdefault is not null
           then E'DEFAULT = ' || quote_nullable(t.typdefault)
         end,
         case when t.typelem <> 0 then E'ELEMENT = ' || format_type(t.typelem,null) end,
         'DELIMITER = ' || quote_nullable(t.typdelim),
         'COLLATABLE = ' || case when t.typcollation <> 0 then 'true' else 'false' end
         ], E',\n  ')
       || E'\n);\n\n'
  from pg_type t
 where oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_type_range(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$
select 'CREATE TYPE ' || format_type($1,null) || ' AS RANGE ('
       || E'\n  SUBTYPE = ' || format_type(r.rngsubtype,null)
       || coalesce(E',\n  SUBTYPE_OPCLASS = ' || quote_ident(opc.opcname),'')
       || case
            when length(col.collcollate) > 0
            then E',\n  COLLATION = ' || quote_ident(col.collcollate::text)
            else ''
          end
       || coalesce(E',\n  CANONICAL = ' || nullif(cast(r.rngcanonical::regproc as text),'-'),'')
       || coalesce(E',\n  SUBTYPE_DIFF = ' || nullif(cast(r.rngsubdiff::regproc as text),'-'),'')
       || E'\n);\n\n'
  from pg_range r
  left join pg_opclass opc on (opc.oid=r.rngsubopc)
  left join pg_collation col on (col.oid=r.rngcollation)
 where r.rngtypid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_type_enum(regtype)
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
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_type_domain(regtype)
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
       || E' AS ' || format_type(t.typbasetype,typtypmod)
       || coalesce(E'\n  '||(select string_agg(definition,E'\n  ') from cc),'')
       || case
            when length(col.collcollate) > 0
            then E'\n  COLLATE ' || quote_ident(col.collcollate::text)
            else ''
          end
       || coalesce(E'\n  DEFAULT ' || t.typdefault, '')
       || E';\n\n'
  from pg_type t
  left join pg_collation col on (col.oid=t.typcollation)
 where t.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_index(regclass)
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
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_class(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from ddlx_identify($1)),

 comments as (
   select 'COMMENT ON COLUMN ' || text($1) || '.' || quote_ident(name) ||
          ' IS ' || quote_nullable(comment) || ';' as cc
     from ddlx_describe($1)
    where comment IS NOT NULL
 ),

 settings as (
   select 'ALTER ' || obj.kind || ' ' || text($1) || ' SET (' ||
          quote_ident(option_name)||'='||quote_nullable(option_value) ||');' as ss
     from pg_options_to_table((select reloptions from pg_class where oid = $1))
     join obj on (true)
 )

 select ddlx_banner(obj.name,obj.kind,obj.namespace,obj.owner)
  ||
 case
  when obj.kind in ('VIEW','MATERIALIZED VIEW') then ddlx_create_view($1)
  when obj.kind in ('TABLE','TYPE','FOREIGN TABLE') then ddlx_create_table($1)
  when obj.kind in ('SEQUENCE') then ddlx_create_sequence($1)
  when obj.kind in ('INDEX') then ddlx_create_index($1)
  else '-- UNSUPPORTED CLASS: '||obj.kind
 end
  || E'\n' ||
  case when obj.kind not in ('TYPE') then ddlx_comment($1) else '' end
  ||
  coalesce((select string_agg(cc,E'\n')||E'\n' from comments),'')
  ||
  coalesce(E'\n'||(select string_agg(ss,E'\n')||E'\n' from settings),'')
  || E'\n'
    from obj

$function$ strict;

---------------------------------------------------



CREATE OR REPLACE FUNCTION ddlx_alter_table_defaults(regclass)
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
   from ddlx_describe($1)
  where "default" is not null
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_default(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
  select format(E'ALTER TABLE %s ALTER %I SET DEFAULT %s;\n\n',
          cast(c.oid::regclass as text),
          a.attname,
          def.adsrc)
    from pg_attrdef def
    join pg_class c on c.oid = def.adrelid
    join pg_attribute a on c.oid = a.attrelid and a.attnum = def.adnum
   where def.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_drop_default(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
  select format(E'ALTER TABLE %s ALTER %I DROP DEFAULT;\n',
          cast(c.oid::regclass as text),
          a.attname,
          def.adsrc)
    from pg_attrdef def
    join pg_class c on c.oid = def.adrelid
    join pg_attribute a on c.oid = a.attrelid and a.attnum = def.adnum
   where def.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_constraints(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with cs as (
  select
   'ALTER TABLE ' || text(regclass(regclass)) ||
   ' ADD CONSTRAINT ' || quote_ident(constraint_name) ||
   E'\n  ' || constraint_definition as sql
    from ddlx_get_constraints($1)
   order by constraint_type desc, sysid
 )
 select coalesce(string_agg(sql,E';\n') || E';\n\n','')
   from cs
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_constraint(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 select format(
   E'ALTER %s %s ADD CONSTRAINT %I\n  %s;\n',
   case
     when t.oid is not null then 'DOMAIN'
     else 'TABLE'
   end,
   coalesce(cast(t.oid::regtype as text),
            cast(r.oid::regclass as text)),
   c.conname,
   pg_get_constraintdef(c.oid,true))
   from pg_constraint c
   left join pg_class r on (c.conrelid = r.oid)
   left join pg_type t on (c.contypid = t.oid)
  where c.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_drop_constraint(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 select format(
   E'ALTER %s %s DROP CONSTRAINT %I;\n',
   case
     when t.oid is not null then 'DOMAIN'
     else 'TABLE'
   end,
   coalesce(cast(t.oid::regtype as text),
            cast(r.oid::regclass as text)),
   c.conname)
   from pg_constraint c
   left join pg_class r on (c.conrelid = r.oid)
   left join pg_type t on (c.contypid = t.oid)
  where c.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_rules(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
  select coalesce(string_agg(rule_definition,E'\n')||E'\n\n','')
    from ddlx_get_rules()
   where regclass = $1
     and rule_definition is not null
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_triggers(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with tg as (
  select trigger_definition as sql
 from ddlx_get_triggers($1) where is_constraint is null
 order by trigger_name
 -- per SQL triggers get called in order created vs name as in PostgreSQL
 )
 select coalesce(string_agg(sql,E';\n')||E';\n\n','')
   from tg
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_trigger(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 select pg_get_triggerdef($1,true)
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_drop_trigger(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 select format(
          E'DROP TRIGGER %I ON %s;\n',
          t.tgname,cast(c.oid::regclass as text))
   from pg_trigger t join pg_class c on (t.tgrelid=c.oid)
  where t.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_indexes(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
 with ii as (select * from ddlx_get_indexes($1) order by name)
 SELECT coalesce( string_agg(indexdef||E';\n','') || E'\n' , '')
   FROM ii
  WHERE constraint_name is null
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_alter_owner(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from ddlx_identify($1))
 select
   case
     when obj.kind = 'INDEX' then ''
     else 'ALTER '||sql_kind||' '||sql_identifier||
          ' OWNER TO '||quote_ident(owner)||E';\n'
   end
  from obj
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_aggregate(regproc)
 RETURNS text
 LANGUAGE sql
AS $function$
  with obj as (select * from ddlx_identify($1))
select 'CREATE AGGREGATE ' || obj.sql_identifier || ' (' || E'\n '
       || E' SFUNC = ' || cast(a.aggtransfn::regproc as text)
       || E',\n  STYPE = ' || format_type(a.aggtranstype,null)
       || case when a.aggtransspace>0 then E',\n  SSPACE = '||a.aggtransspace else '' end
       || coalesce(E',\n  FINALFUNC = ' || nullif(cast(a.aggfinalfn::regproc as text),'-'),'')
       || case when a.aggfinalextra then E',\n  FINALFUNC_EXTRA' else '' end
       || coalesce(E',\n  COMBINEFUNC = ' || nullif(cast(a.aggcombinefn::regproc as text),'-'),'')
       || coalesce(E',\n  SERIALFUNC = ' || nullif(cast(a.aggserialfn::regproc as text),'-'),'')
       || coalesce(E',\n  DESERIALFUNC = ' || nullif(cast(a.aggdeserialfn::regproc as text),'-'),'')
       || coalesce(E',\n  INITCOND = ' || quote_literal(a.agginitval),'')
       || coalesce(E',\n  MSFUNC = ' || nullif(cast(a.aggmtransfn::regproc as text),'-'),'')
       || coalesce(E',\n  MINVFUNC = ' || nullif(cast(a.aggminvtransfn::regproc as text),'-'),'')
       || case when a.aggmtranstype>0 then E',\n  MSTYPE = '||format_type(a.aggmtranstype,null) else '' end
       || case when a.aggmtransspace>0 then E',\n  MSSPACE = '||a.aggmtransspace else '' end
       || coalesce(E',\n  MFINALFUNC = ' || nullif(cast(a.aggmfinalfn::regproc as text),'-'),'')
       || case when a.aggmfinalextra then E',\n  MFINALFUNC_EXTRA' else '' end
       || coalesce(E',\n  MINITCOND = ' || quote_literal(a.aggminitval),'')
       || case
            when a.aggsortop>0
            then E',\n  SORTOP = '||cast(a.aggsortop::regoperator as text)
            else ''
          end
       || E',\n  PARALLEL = '
       || case p.proparallel
            when 's' then 'SAFE'
            when 'r' then 'RESTRICTED'
            when 'u' then 'UNSAFE'
            else quote_literal(p.proparallel)
          end
       || case a.aggkind
            when 'h' then E',\n  HYPOTHETICAL'
            else ''
          end
       || E'\n);\n'
  from pg_aggregate a join obj on (true) join pg_proc p on p.oid = a.aggfnoid
 where a.aggfnoid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_function(regproc)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from ddlx_identify($1))
 select
  ddlx_banner(sql_identifier,obj.sql_kind,namespace,owner) ||
  case obj.sql_kind
    when 'AGGREGATE' then ddlx_create_aggregate($1)
    else trim(trailing E'\n' from pg_get_functiondef($1)) || E';\n'
   end || E'\n'
    || ddlx_comment($1) || E'\n'
   from obj
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_role(regrole)
 RETURNS text
 LANGUAGE sql
AS $function$
with
q1 as (
 select
   'CREATE ' || case when rolcanlogin then 'USER' else 'GROUP' end
   ||' '||quote_ident(rolname)|| E';\n' ||
   'ALTER ROLE '|| quote_ident(rolname) || E' WITH\n  ' ||
   case when rolcanlogin then 'LOGIN' else 'NOLOGIN' end || E'\n  ' ||
   case when rolsuper then 'SUPERUSER' else 'NOSUPERUSER' end || E'\n  ' ||
   case when rolinherit then 'INHERIT' else 'NOINHERIT' end || E'\n  ' ||
   case when rolcreatedb then 'CREATEDB' else 'NOCREATEDB' end || E'\n  ' ||
   case when rolcreaterole then 'CREATEROLE' else 'NOCREATEROLE' end || E'\n  ' ||
   case when rolreplication then 'REPLICATION' else 'NOREPLICATION' end || E';\n  ' ||
-- 9.5+ case when rolbypassrls then 'BYPASSRLS' else 'NOBYPASSRLS' end || E';\n' ||
   case
     when description is not null
     then E'\n'
          ||'COMMENT ON ROLE '||quote_ident(rolname)
          ||' IS '||quote_literal(description)||E';\n'
     else ''
   end || E'\n' ||
   case when rolpassword is not null
        then 'ALTER ROLE '|| quote_ident(rolname)||
             ' ENCRYPTED PASSWORD '||quote_literal(rolpassword)||E';\n'
        else ''
   end ||
   case when rolvaliduntil is not null
        then 'ALTER ROLE '|| quote_ident(rolname)||
             ' VALID UNTIL '||quote_nullable(rolvaliduntil)||E';\n'
        else ''
   end ||
   case when rolconnlimit>=0
        then 'ALTER ROLE '|| quote_ident(rolname)||
             ' CONNECTION LIMIT '||rolconnlimit||E';\n'
        else ''
   end ||
   E'\n' as ddl
   from pg_authid a
   left join pg_shdescription d on d.objoid=a.oid
  where a.oid = $1
 ),
q2 as (
 select string_agg('ALTER ROLE ' || quote_ident(rolname)
                   ||' SET '||pg_roles.rolconfig[i]||E';\n','')
    as ddl_config
  from pg_roles,
  generate_series(
     (select array_lower(rolconfig,1) from pg_roles where oid=$1),
     (select array_upper(rolconfig,1) from pg_roles where oid=$1)
  ) as generate_series(i)
 where oid = $1
 )
select ddl||coalesce(ddl_config||E'\n','')
  from q1,q2;
$function$ strict
set datestyle = iso;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_event_trigger(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from pg_event_trigger where oid = $1)
 select
    'CREATE EVENT TRIGGER ' || quote_ident(obj.evtname) ||
    ' ON ' || obj.evtname || E'\n' ||
    case
    when obj.evttags is not null
    then '  WHEN tag IN ' ||
      (select '(' || string_agg(quote_nullable(u),', ') || ')'
         from unnest(obj.evttags) as u)
        || E'\n'
    else ''
    end ||
    '  EXECUTE PROCEDURE ' || cast(obj.evtfoid as regprocedure) || E';\n'
    || ddlx_comment($1)
    || ddlx_alter_owner($1)
   from obj;
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_foreign_data_wrapper(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from pg_foreign_data_wrapper where oid = $1)
 select
    'CREATE FOREIGN DATA WRAPPER ' || quote_ident(obj.fdwname) || E'\n' ||
    case
    when obj.fdwhandler is not null
    then '  HANDLER ' || cast(obj.fdwhandler as regproc)
    else '  NO HANDLER'
    end || E'\n' ||
    case
    when obj.fdwvalidator is not null
    then '  VALIDATOR ' || cast(obj.fdwvalidator as regproc)
    else '  NO VALIDATOR'
    end ||
    coalesce(E'\nOPTIONS (\n'||
      (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value),
              E',\n')
         from pg_options_to_table(obj.fdwoptions))||E'\n)'
    ,'') || E';\n'
    || ddlx_comment($1)
    || ddlx_alter_owner($1)
   from obj;
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_server(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from pg_foreign_server where oid = $1)
 select
    'CREATE SERVER ' || quote_ident(obj.srvname) ||
    coalesce(E'\nTYPE ' || quote_literal(obj.srvtype),'') ||
    coalesce(E'\nVERSION ' || quote_literal(obj.srvversion),'') ||
    E'\nFOREIGN DATA WRAPPER ' ||
      (select quote_ident(fdwname)
         from pg_foreign_data_wrapper
        where oid = obj.srvfdw) ||
    coalesce(E'\nOPTIONS (\n'||
      (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value),
              E',\n')
         from pg_options_to_table(obj.srvoptions))||E'\n)'
    ,'') || E';\n'
    || ddlx_comment($1)
    || ddlx_alter_owner($1)
   from obj;
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_user_mapping(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
 with obj as (select * from ddlx_identify($1))
 select
    'CREATE USER MAPPING ' || obj.sql_identifier ||
    coalesce(E'\nOPTIONS (\n'||
      (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value),
              E',\n')
         from pg_options_to_table(um.umoptions))||E'\n)'
    ,'') || E';\n'
   from obj
   join pg_user_mapping um ON um.oid = obj.oid;
$function$ strict;

---------------------------------------------------
-- Grants
---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_grants(regclass)
 RETURNS text
 LANGUAGE sql
 AS $function$
 with obj as (select * from ddlx_identify($1))
 select
   coalesce(
    string_agg(format(
     E'GRANT %s ON %s TO %s%s;\n',
        privilege_type,
        cast($1 as text),
        case grantee
          when 'PUBLIC' then 'PUBLIC'
          else quote_ident(grantee)
        end,
  case is_grantable
          when 'YES' then ' WITH GRANT OPTION'
          else ''
        end), ''),
    '')
 FROM information_schema.table_privileges g
 join obj on (true)
 WHERE table_schema=obj.namespace
   AND table_name=obj.name
   AND grantee<>obj.owner
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_grants(regproc)
 RETURNS text
 LANGUAGE sql
 AS $function$
 with obj as (select * from ddlx_identify($1))
 select
   format(E'REVOKE ALL ON FUNCTION %s FROM PUBLIC;\n',
          text($1::regprocedure)) ||
   coalesce(
    string_agg (format(
     E'GRANT %s ON FUNCTION %s TO %s%s;\n',
     privilege_type,
        text($1::regprocedure),
        CASE grantee
          WHEN 'PUBLIC' THEN 'PUBLIC'
          ELSE quote_ident(grantee)
        END,
  CASE is_grantable
          WHEN 'YES' THEN ' WITH GRANT OPTION'
    ELSE ''
        END), ''),
    '')
 FROM information_schema.routine_privileges g
 join obj on (true)
 WHERE routine_schema=obj.namespace
   AND specific_name=obj.name||'_'||obj.oid
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_grants(regrole)
 RETURNS text
 LANGUAGE sql
 AS $function$
with
q as (
 select format(E'GRANT %I TO %I%s;\n',
               cast(roleid::regrole as text),
               cast(member::regrole as text),
               case
                 when admin_option then ' WITH ADMIN OPTION'
                 else ''
                end)
        as ddl1
   from pg_auth_members where (member = $1 or roleid = $1)
  order by roleid = $1,
           cast(roleid::regrole as text),
           cast(member::regrole as text)
)
select coalesce(string_agg(ddl1,'')||E'\n','')
  from q
$function$ strict;

---------------------------------------------------
-- Dependancy handling
---------------------------------------------------

create or replace function ddlx_get_dependants_recursive(
 in oid,
 out depth int, out classid regclass, out objid oid, out objsubid integer,
 out refclassid regclass, out refobjid oid, out refobjsubid integer,
 out deptype "char"
)
returns setof record as $$
with recursive
  tree(depth,classid,objid,objsubid,refclassid,refobjid,refobjsubid,deptype,edges)
as (
select 1,
       case when r.oid is not null
            then 'pg_class'::regclass
            else d.classid::regclass
       end as classid,
       coalesce(r.ev_class,d.objid) as objid,
       d.objsubid,
       d.refclassid,
       d.refobjid,
       d.refobjsubid,
       d.deptype,
       to_jsonb(array[array[d.refobjid::int,d.objid::int]])
  from pg_depend d
  left join pg_rewrite r on
       (r.oid = d.objid and r.ev_type = '1' and r.rulename = '_RETURN')
 where d.refobjid = $1 and r.ev_class is distinct from d.refobjid
 union all
select depth+1,
       case when r.oid is not null
            then 'pg_class'::regclass
            else d.classid::regclass
       end as classid,
       coalesce(r.ev_class,d.objid) as objid,
       d.objsubid,
       d.refclassid,
       d.refobjid,
       d.refobjsubid,
       d.deptype,
       t.edges ||
       to_jsonb(array[array[d.refobjid::int,d.objid::int]])
  from tree t
  join pg_depend d on (d.refobjid=t.objid)
  left join pg_rewrite r on
       (r.oid = d.objid and r.ev_type = '1' and r.rulename = '_RETURN')
 where r.ev_class is distinct from d.refobjid
   and not ( t.edges @> to_jsonb(array[array[d.refobjid::int,d.objid::int]]) )
)
select distinct
       depth,
       classid,
       objid,
       objsubid,
       refclassid,
       refobjid,
       refobjsubid,
       deptype
  from tree
$$ language sql;

---------------------------------------------------

create or replace function ddlx_get_dependants(
 in oid,
 out depth int, out classid regclass, out objid oid
)
returns setof record as $$
with
q as (
  select distinct depth,classid,objid
    from ddlx_get_dependants_recursive($1)
   where deptype = 'n'
)
select depth,classid,objid
  from q
 where (objid,depth) in (select objid,max(depth) from q group by objid)
 order by depth,objid
$$ language sql;

---------------------------------------------------
-- Main script generating functions
---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$ select null::text $function$;
-- will be redefined later

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regclass)
 RETURNS text
 LANGUAGE sql
AS $function$
   select
     ddlx_create_class($1)
     || ddlx_alter_table_defaults($1)
     || ddlx_create_constraints($1)
     || ddlx_create_indexes($1)
     || ddlx_create_triggers($1)
     || ddlx_create_rules($1)
     || ddlx_alter_owner($1)
     || ddlx_grants($1)
    from pg_class c
   where c.oid = $1 and c.relkind <> 'c'
   union
  select ddlx_create(t.oid::regtype)
    from pg_class c
    left join pg_type t on (c.oid=t.typrelid)
   where c.oid = $1 and c.relkind = 'c'
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regclass)
     IS 'Get SQL CREATE statement for a table, view, sequence or index';


---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regproc)
 RETURNS text
 LANGUAGE sql
AS $function$
   select
     ddlx_create_function($1)
     || ddlx_alter_owner($1)
     || ddlx_grants($1)
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regproc)
     IS 'Get SQL CREATE statement for a routine';

CREATE OR REPLACE FUNCTION ddlx_create(regprocedure)
 RETURNS text
 LANGUAGE sql
AS $function$
   select ddlx_create($1::regproc)
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regprocedure)
     IS 'Get SQL CREATE statement for a routine';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regoper)
 RETURNS text
 LANGUAGE sql
AS $function$
select format(
         E'CREATE OPERATOR %s (\n%s%s%s%s%s%s%s%s%s\n);\n\n',
         cast(o.oid::regoper as text),
         E'  PROCEDURE = ' || cast(o.oprcode::regproc as text),
         case when o.oprleft <> 0 then E',\n  LEFTARG = ' || format_type(o.oprleft,null) end,
         case when o.oprright <> 0 then E',\n  RIGHTARG = ' || format_type(o.oprright,null) end,
         case when o.oprcom <> 0
              then E',\n  COMMUTATOR = OPERATOR('||cast(o.oprcom::regoper as text)||')' end,
         case when o.oprnegate <> 0
              then E',\n  NEGATOR = OPERATOR('||cast(o.oprnegate::regoper as text)||')' end,
         case when o.oprrest <> 0 then E',\n  RESTRICT = ' || cast(o.oprrest::regproc as text) end,
         case when o.oprjoin <> 0 then E',\n  JOIN = ' || cast(o.oprjoin::regproc as text) end,
         case when o.oprcanhash then E',\n  HASHES' end,
         case when o.oprcanmerge then E',\n  MERGES' end
  )
  || ddlx_comment($1)
     || ddlx_alter_owner($1)
  from pg_operator o
 where oid = $1
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regoper)
     IS 'Get SQL CREATE statement for an operator';

CREATE OR REPLACE FUNCTION ddlx_create(regoperator)
 RETURNS text
 LANGUAGE sql
AS $function$
   select ddlx_create($1::regoper)
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regoperator)
     IS 'Get SQL CREATE statement for an operator';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regconfig)
 RETURNS text
 LANGUAGE sql
AS $function$
with cfg as (select * from pg_ts_config where oid = $1),
     prs as (select * from ddlx_identify(
              (select p.oid
                 from pg_ts_parser p
                 join cfg on p.oid = cfg.cfgparser
             )))
select format(E'CREATE TEXT SEARCH CONFIGURATION %s ( PARSER = %s );\n',
              cast($1 as text),
              prs.sql_identifier)
    || ddlx_comment($1)
       || ddlx_alter_owner($1)
  from prs;
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regconfig)
     IS 'Get SQL CREATE statement for a text search configuration';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regdictionary)
 RETURNS text
 LANGUAGE sql
AS $function$
with dict as (select * from pg_ts_dict where oid = $1),
     tmpl as (select * from ddlx_identify(
              (select t.oid
                 from pg_ts_template t
                 join dict on t.oid = dict.dicttemplate
             )))
select format(E'CREATE TEXT SEARCH DICTIONARY %s\n  ( TEMPLATE = %s%s );\n',
       cast($1 as text),
       tmpl.sql_identifier,
       ', '||dict.dictinitoption)
    || ddlx_comment($1)
       || ddlx_alter_owner($1)
  from dict,tmpl;
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regdictionary)
     IS 'Get SQL CREATE statement for a text search dictionary';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_text_search_parser(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
with obj as (select * from ddlx_identify($1))
select format(E'CREATE TEXT SEARCH PARSER %s (\n  %s\n);\n',obj.sql_identifier,
         array_to_string(array[
           'START = ' || nullif(cast(p.prsstart::regproc as text),'-'),
           'GETTOKEN = ' || nullif(cast(p.prstoken::regproc as text),'-'),
           'END = ' || nullif(cast(p.prsend::regproc as text),'-'),
           'LEXTYPES = ' || nullif(cast(p.prslextype::regproc as text),'-'),
           'HEADLINE = ' || nullif(cast(p.prsheadline::regproc as text),'-')
           ],E',\n  ')
        )
        || ddlx_comment($1)
  from pg_ts_parser as p, obj
 where p.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_text_search_template(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
with obj as (select * from ddlx_identify($1))
select format(E'CREATE TEXT SEARCH TEMPLATE %s (\n  %s\n);\n',obj.sql_identifier,
         array_to_string(array[
           'INIT = ' || nullif(cast(t.tmplinit::regproc as text),'-'),
           'LEXIZE = ' || nullif(cast(t.tmpllexize::regproc as text),'-')
           ],E',\n  ')
        )
        || ddlx_comment($1)
  from pg_ts_template as t, obj
 where t.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_cast(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
with obj as (select * from ddlx_identify($1))
select format(E'CREATE CAST %s\n  ',obj.sql_identifier)
        || case
           when c.castmethod = 'i'
           then 'WITH INOUT'
           when c.castfunc>0
           then 'WITH FUNCTION '||cast(c.castfunc::regprocedure as text)
           else 'WITHOUT FUNCTION'
           end
        || case c.castcontext
           when 'a' then E'\n  AS ASSIGNMENT'
           when 'i' then E'\n  AS IMPLICIT'
           else ''
           end
        || E';\n'
        || ddlx_comment($1)
  from pg_cast as c, obj
 where c.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_collation(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
with obj as (select * from ddlx_identify($1))
select format(E'CREATE COLLATION %s (\n  %s\n);\n',obj.sql_identifier,
         array_to_string(array[
           'LC_COLLATE = '|| quote_nullable(collcollate),
           'LC_CTYPE = ' || quote_nullable(collctype)
           ],E',\n  ')
        )
        || ddlx_comment($1)
        || ddlx_alter_owner($1)
  from pg_collation as c, obj
 where c.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create_conversion(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
with obj as (select * from ddlx_identify($1))
select format(E'CREATE %sCONVERSION %s\n  FOR %L TO %L FROM %s;\n',
  case when c.condefault then 'DEFAULT ' end,
  obj.sql_identifier,
  pg_encoding_to_char(c.conforencoding),
  pg_encoding_to_char(c.contoencoding),
  cast(c.conproc::regproc as text)
    )
        || ddlx_comment($1)
        || ddlx_alter_owner($1)
  from pg_conversion as c, obj
 where c.oid = $1
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regnamespace)
 RETURNS text
 LANGUAGE sql
AS $function$
select format(E'CREATE SCHEMA %s;\n',cast($1 as text))
    || ddlx_comment($1)
       || ddlx_alter_owner($1)
  from pg_namespace n
 where oid = $1
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regnamespace)
     IS 'Get SQL CREATE statement for a schema';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regrole)
 RETURNS text
 LANGUAGE sql
AS $function$
   select
     ddlx_create_role($1)
     || ddlx_grants($1)
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regrole)
     IS 'Get SQL CREATE statement for a role';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(regtype)
 RETURNS text
 LANGUAGE sql
AS $function$
   select ddlx_create_class(c.oid::regclass) -- type
          || ddlx_comment(t.oid)
          || ddlx_alter_owner(t.oid)
     from pg_type t
     join pg_class c on (c.oid=t.typrelid)
    where t.oid = $1 and t.typtype = 'c' and c.relkind = 'c'
    union
   select ddlx_create(c.oid::regclass) -- table, etc
     from pg_type t
     join pg_class c on (c.oid=t.typrelid)
    where t.oid = $1 and t.typtype = 'c' and c.relkind <> 'c'
    union
   select case t.typtype
          when 'e' then ddlx_create_type_enum(t.oid)
          when 'd' then ddlx_create_type_domain(t.oid)
          when 'b' then ddlx_create_type_base(t.oid)
          when 'r' then ddlx_create_type_range(t.oid)
    else '-- UNSUPPORTED TYPE: ' || t.typtype || E'\n'
    end
          || ddlx_comment(t.oid)
          || ddlx_alter_owner(t.oid)
     from pg_type t
    where t.oid = $1 and t.typtype <> 'c'
$function$ strict;

COMMENT ON FUNCTION ddlx_create(regtype)
     IS 'Get SQL CREATE statement for a user defined data type';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_create(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
  with obj as (select * from ddlx_identify($1))
  select case obj.classid
 when 'pg_class'::regclass
 then ddlx_create(oid::regclass)
 when 'pg_proc'::regclass
 then ddlx_create(oid::regproc)
 when 'pg_type'::regclass
 then ddlx_create(oid::regtype)
 when 'pg_operator'::regclass
 then ddlx_create(oid::regoper)
 when 'pg_roles'::regclass
 then ddlx_create(oid::regrole)
 when 'pg_namespace'::regclass
 then ddlx_create(oid::regnamespace)
 when 'pg_ts_config'::regclass
 then ddlx_create(oid::regconfig)
 when 'pg_ts_dict'::regclass
 then ddlx_create(oid::regdictionary)
 when 'pg_ts_parser'::regclass
 then ddlx_create_text_search_parser(oid)
 when 'pg_ts_template'::regclass
 then ddlx_create_text_search_template(oid)
 when 'pg_constraint'::regclass
 then ddlx_create_constraint(oid)
 when 'pg_trigger'::regclass
 then ddlx_create_trigger(oid)
 when 'pg_attrdef'::regclass
 then ddlx_create_default(oid)
 when 'pg_event_trigger'::regclass
 then ddlx_create_event_trigger(oid)
 when 'pg_foreign_data_wrapper'::regclass
 then ddlx_create_foreign_data_wrapper(oid)
 when 'pg_foreign_server'::regclass
 then ddlx_create_server(oid)
 when 'pg_user_mapping'::regclass
 then ddlx_create_user_mapping(oid)
 when 'pg_cast'::regclass
 then ddlx_create_cast(oid)
 when 'pg_collation'::regclass
 then ddlx_create_collation(oid)
 else
   case
  when kind is not null
  then format(E'-- CREATE UNSUPPORTED OBJECT: %s %s\n',text($1),sql_kind)
  else format(E'-- CREATE UNIDENTIFIED OBJECT: %s\n',text($1))
    end
   end
   as ddl
    from obj
$function$ strict;

COMMENT ON FUNCTION ddlx_create(oid)
     IS 'Get SQL CREATE statement for a generic object by object id';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_drop(oid)
 RETURNS text
 LANGUAGE sql
 AS $function$
 with obj as (select * from ddlx_identify($1))
 select case obj.classid
   when 'pg_constraint'::regclass
   then ddlx_drop_constraint(oid)
   when 'pg_trigger'::regclass
   then ddlx_drop_trigger(oid)
   when 'pg_attrdef'::regclass
   then ddlx_drop_default(oid)
   else
  case
    when kind is not null
    then format(E'DROP %s %s;\n',obj.sql_kind, obj.sql_identifier)
    else format(E'-- DROP UNIDENTIFIED OBJECT: %s\n',text($1))
   end
  end
  as ddl
   from obj
$function$ strict;

COMMENT ON FUNCTION ddlx_drop(oid)
     IS 'Get SQL DROP statement for an object by object id';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_parts(
 IN oid,
 OUT ddl_create text, OUT ddl_drop text,
 OUT ddl_create_deps text, OUT ddl_drop_deps text)
 RETURNS record
 LANGUAGE sql
AS $function$
with
ddl as (
select row_number() over() as n,
       ddlx_drop(objid),
       ddlx_create(objid),
       objid
  from ddlx_get_dependants($1)
)
select ddlx_create($1) as ddl_create,
       ddlx_drop($1) as ddl_drop,
       string_agg(ddlx_create,E'\n' order by n) as ddl_create_deps,
       string_agg(ddlx_drop,'' order by n desc) as ddl_drop_deps
  from ddl
$function$ strict;

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_script(oid)
 RETURNS text
 LANGUAGE sql
AS $function$
select E'BEGIN;\n\n'||
       format(
         E'/*\n%s%s*/\n\n%s%s',
         ddl_drop_deps||E'\n',
         ddl_drop,
         ddl_create,
         E'\n-- DEPENDANTS\n\n'||ddl_create_deps
       )||
       E'\nEND;\n'
  from ddlx_parts($1)
$function$ strict;

COMMENT ON FUNCTION ddlx_script(oid)
     IS 'Get SQL DDL script for an object and dependants by object id';

---------------------------------------------------

CREATE OR REPLACE FUNCTION ddlx_script(sql_identifier text)
 RETURNS text
 LANGUAGE sql
AS $function$
  select case
    when strpos($1,'(')>0
    then ddlx_script(cast($1 as regprocedure)::oid)
    else ddlx_script(cast($1 as regtype)::oid)
     end
$function$ strict;

COMMENT ON FUNCTION ddlx_script(text)
     IS 'Get SQL DDL script for an object and dependants by object name';
