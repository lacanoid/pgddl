--------------------------------------------------------------- ---------------
--  DDL eXtractor functions
--  version 0.33 lacanoid@ljudmila.org
--------------------------------------------------------------- ---------------

--------------------------------------------------------------- ---------------
--  Helpers for digesting system catalogs
--------------------------------------------------------------- ---------------

-- UPGRADE NOTE: ddlx_identify(oid) now returns SETOF record, which CREATE OR
-- REPLACE cannot change. When upgrading an installed ddlx run first:
--   DROP FUNCTION ddlx_identify(oid);

-- Exact identification: the object is named by its catalog (classid) and oid.
-- Returns at most one row.  For a table's row type (or a composite type's
-- table) the canonical object is returned, so the returned classid may
-- differ from the one given.
CREATE OR REPLACE FUNCTION ddlx_identify(
  IN regclass, IN oid,
  OUT oid oid, OUT classid regclass, 
  OUT name name,  OUT namespace name,  
  OUT owner name, OUT sql_kind text, 
  OUT sql_identifier text, OUT acl aclitem[])
 RETURNS record LANGUAGE sql STABLE AS $$
  WITH 
  rel_kind(k,v) AS (
         VALUES ('r','TABLE'),
                ('p','TABLE'),
                ('v','VIEW'),
                ('i','INDEX'),
                ('I','INDEX'),
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
  SELECT coalesce(t.oid,c.oid),
         case when t.oid is not null then 'pg_type'::regclass
              else 'pg_class'::regclass end,
         c.relname AS name, n.nspname AS namespace,
         pg_get_userbyid(c.relowner) AS owner,
         coalesce(cc.v,c.relkind::text) AS sql_kind,
         cast($2::regclass AS text) AS sql_identifier,
         relacl as acl
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN pg_type t 
      ON t.typrelid=c.oid AND t.typtype='c' AND c.relkind='c'
    LEFT JOIN rel_kind AS cc on cc.k = c.relkind
   WHERE $1 = 'pg_class'::regclass AND c.oid = $2
   UNION ALL
  SELECT p.oid,'pg_proc'::regclass,
         p.proname AS name, n.nspname AS namespace, 
         pg_get_userbyid(p.proowner) AS owner,
#if 11
         case p.prokind
           when 'f' then 'FUNCTION'
           when 'a' then 'AGGREGATE'
           when 'p' then 'PROCEDURE'
           when 'w' then 'WINDOW FUNCTION'
         end 
#else
         case
           when p.proisagg then 'AGGREGATE'
           else 'FUNCTION' 
         end 
#end
         AS sql_kind,
         cast($2::regprocedure AS text) AS sql_identifier,
         proacl as acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE $1 = 'pg_proc'::regclass AND p.oid = $2
   UNION ALL
  SELECT coalesce(c.oid,t.oid),
         case when c.oid is not null then 'pg_class'::regclass
   else 'pg_type'::regclass end,
         t.typname AS name, n.nspname AS namespace, 
         pg_get_userbyid(t.typowner) AS owner,
         coalesce(cc.v,tt.v2,t.typtype::text) AS sql_kind,
         format_type($2,null) AS sql_identifier,
#if 9.2
         typacl as acl
#else
         null as acl
#end
    FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    LEFT JOIN typ_type AS tt ON tt.k = t.typtype 
    LEFT JOIN pg_class AS c 
      ON c.oid = t.typrelid AND t.typtype='c' AND c.relkind<>'c'
    LEFT JOIN rel_kind AS cc ON cc.k = c.relkind
   WHERE $1 = 'pg_type'::regclass AND t.oid = $2
   UNION ALL
  SELECT r.oid,'pg_roles'::regclass,
         r.rolname as name, null as namespace, null as owner,
         'ROLE' as sql_kind,
         quote_ident(r.rolname) as sql_identifier,
         null as acl
    FROM pg_roles r
   WHERE $1 in ('pg_roles'::regclass,'pg_authid'::regclass) AND r.oid = $2
   UNION ALL
  SELECT r.oid,'pg_rewrite'::regclass,
         r.rulename as name, null as namespace, null as owner,
         'RULE' as sql_kind,
         quote_ident(r.rulename)||' ON '|| 
           cast(c.oid::regclass as text) sql_identifier,
         null as acl
    FROM pg_rewrite r JOIN pg_class c on (c.oid = r.ev_class)
   WHERE $1 = 'pg_rewrite'::regclass AND r.oid = $2
   UNION ALL
  SELECT n.oid,'pg_namespace'::regclass,
         n.nspname as name, current_database() as namespace, 
         pg_get_userbyid(n.nspowner) AS owner,
         'SCHEMA' as sql_kind,
         quote_ident(n.nspname) as sql_identifier,
         nspacl as acl
    FROM pg_namespace n join pg_roles r on r.oid = n.nspowner
   WHERE $1 = 'pg_namespace'::regclass AND n.oid = $2
   UNION ALL
  SELECT con.oid,'pg_constraint'::regclass,
         con.conname as name,
         c.relname as namespace, null as owner, 
         'CONSTRAINT' as sql_kind,
         quote_ident(con.conname)
         ||coalesce(' ON '||cast(c.oid::regclass as text),'') 
           as sql_identifier,
         null as acl
    FROM pg_constraint con 
    left JOIN pg_class c ON (con.conrelid=c.oid)
    LEFT join (
         values ('f','FOREIGN KEY'), ('c','CHECK'), ('x','EXCLUDE'),
                ('u','UNIQUE'), ('p','PRIMARY KEY'), ('t','TRIGGER'),
		            ('n','NOT NULL') )
             as tt on tt.column1 = con.contype
   WHERE $1 = 'pg_constraint'::regclass AND con.oid = $2
#if 14
     AND (c.oid is null or -- hack to hide duplicated oids
          c.relnamespace <> 'pg_catalog'::regnamespace)
#end
   UNION ALL
  SELECT t.oid,'pg_trigger'::regclass,
         t.tgname as name, c.relname as namespace, null as owner,
         'TRIGGER' as sql_kind,
         format('%I ON %s',t.tgname,cast(c.oid::regclass as text)) 
           as sql_identifier,
         null as acl
    FROM pg_trigger t join pg_class c on (t.tgrelid=c.oid)
   WHERE $1 = 'pg_trigger'::regclass AND t.oid = $2
   UNION ALL
  SELECT ad.oid,'pg_attrdef'::regclass,
         a.attname as name, c.relname as namespace, null as owner,
         'DEFAULT' as sql_kind,
         format('%s.%I',cast(c.oid::regclass as text),a.attname) 
           as sql_identifier,
         null as acl
    FROM pg_attrdef ad 
    JOIN pg_class c ON (ad.adrelid=c.oid)
    JOIN pg_attribute a ON (c.oid = a.attrelid and a.attnum=ad.adnum)
   WHERE $1 = 'pg_attrdef'::regclass AND ad.oid = $2
   UNION ALL
  SELECT op.oid,'pg_operator'::regclass,
         op.oprname as name, n.nspname as namespace, 
         pg_get_userbyid(op.oprowner) as owner,
         'OPERATOR' as sql_kind,
         cast(op.oid::regoperator as text) as sql_identifier,
         null as acl
    FROM pg_operator op JOIN pg_namespace n ON n.oid=op.oprnamespace
   WHERE $1 = 'pg_operator'::regclass AND op.oid = $2
   UNION ALL
  SELECT cfg.oid,'pg_ts_config'::regclass,
         cfg.cfgname as name, n.nspname as namespace, 
         pg_get_userbyid(cfg.cfgowner) as owner,
         'TEXT SEARCH CONFIGURATION' as sql_kind,
         cast(cfg.oid::regconfig as text) as sql_identifier,
         null as acl
    FROM pg_ts_config cfg JOIN pg_namespace n ON n.oid=cfg.cfgnamespace
   WHERE $1 = 'pg_ts_config'::regclass AND cfg.oid = $2
   UNION ALL
  SELECT dict.oid,'pg_ts_dict'::regclass,
         dict.dictname as name, n.nspname as namespace, 
         pg_get_userbyid(dict.dictowner) as owner,
         'TEXT SEARCH DICTIONARY' as sql_kind,
         cast(dict.oid::regdictionary as text) as sql_identifier,
         null as acl
    FROM pg_ts_dict dict JOIN pg_namespace n ON n.oid=dict.dictnamespace
   WHERE $1 = 'pg_ts_dict'::regclass AND dict.oid = $2
   UNION ALL
  SELECT prs.oid,'pg_ts_parser'::regclass,
         prs.prsname as name, n.nspname as namespace, null as owner,
         'TEXT SEARCH PARSER' as sql_kind,
         format('%s%I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',prs.prsname) 
           as sql_identifier,
         null as acl
    FROM pg_ts_parser prs JOIN pg_namespace n ON n.oid=prs.prsnamespace
   WHERE $1 = 'pg_ts_parser'::regclass AND prs.oid = $2
   UNION ALL
  SELECT tmpl.oid,'pg_ts_template'::regclass,
         tmpl.tmplname as name, n.nspname as namespace, null as owner,
         'TEXT SEARCH TEMPLATE' as sql_kind,
         format('%s%I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',tmpl.tmplname) 
           as sql_identifier,
         null as acl
    FROM pg_ts_template tmpl JOIN pg_namespace n ON n.oid=tmpl.tmplnamespace
   WHERE $1 = 'pg_ts_template'::regclass AND tmpl.oid = $2
   UNION ALL
  SELECT fdw.oid,'pg_foreign_data_wrapper'::regclass,
         fdw.fdwname as name, null as namespace, 
         pg_get_userbyid(fdw.fdwowner) as owner,
         'FOREIGN DATA WRAPPER' as sql_kind,
         quote_ident(fdw.fdwname) as sql_identifier,
         fdwacl as acl
    FROM pg_foreign_data_wrapper fdw
   WHERE $1 = 'pg_foreign_data_wrapper'::regclass AND fdw.oid = $2
   UNION ALL
  SELECT srv.oid,'pg_foreign_server'::regclass,
         srv.srvname as name, null as namespace, 
         pg_get_userbyid(srv.srvowner) as owner,
         'SERVER' as sql_kind,
         quote_ident(srv.srvname) as sql_identifier,
         srvacl as acl
    FROM pg_foreign_server srv
   WHERE $1 = 'pg_foreign_server'::regclass AND srv.oid = $2
   UNION ALL
  SELECT ums.umid,'pg_user_mapping'::regclass,
         null as name, null as namespace, null as owner, 
         'USER MAPPING' as sql_kind,
         'FOR '||quote_ident(ums.usename)||
         ' SERVER '||quote_ident(ums.srvname) as sql_identifier,
         null as acl
    FROM pg_user_mappings ums
   WHERE $1 = 'pg_user_mapping'::regclass AND ums.umid = $2
   UNION ALL
  SELECT ca.oid,'pg_cast'::regclass,
         null as name, null as namespace, null as owner,
         'CAST' as sql_kind,
         format('(%s AS %s)',
           format_type(ca.castsource,null),
           format_type(ca.casttarget,null)) as sql_identifier,
         null as acl
    FROM pg_cast ca
   WHERE $1 = 'pg_cast'::regclass AND ca.oid = $2
   UNION ALL
  SELECT da.oid,'pg_default_acl'::regclass,
         case da.defaclobjtype
              when 'r' then 'TABLES' when 'S' then 'SEQUENCES' when 'f' then 'FUNCTIONS'
              when 'T' then 'TYPES' when 'n' then 'SCHEMAS' when 'L' then 'LARGE OBJECTS' end as name,
         n.nspname as namespace, 
         pg_get_userbyid(da.defaclrole) as owner,
         'DEFAULT PRIVILEGES' as sql_kind,
         format('FOR ROLE %I%s ON %s', pg_get_userbyid(da.defaclrole),
                case when da.defaclnamespace <> 0 
                     then format(' IN SCHEMA %I', n.nspname) else '' end,
                case da.defaclobjtype
              when 'r' then 'TABLES' when 'S' then 'SEQUENCES' when 'f' then 'FUNCTIONS'
              when 'T' then 'TYPES' when 'n' then 'SCHEMAS' when 'L' then 'LARGE OBJECTS' end) as sql_identifier,
         null as acl   -- the ACL is not a GRANT target; see ddlx_create_default_acl
    FROM pg_default_acl da
    LEFT JOIN pg_namespace n ON n.oid = da.defaclnamespace
   WHERE $1 = 'pg_default_acl'::regclass AND da.oid = $2
   UNION ALL
  SELECT co.oid,'pg_collation'::regclass,
         co.collname as name, n.nspname as namespace, 
         pg_get_userbyid(co.collowner) as owner,
         'COLLATION' as sql_kind,
         format('%s%I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',co.collname) 
           as sql_identifier,
         null as acl
    FROM pg_collation co JOIN pg_namespace n ON n.oid=co.collnamespace
   WHERE $1 = 'pg_collation'::regclass AND co.oid = $2
   UNION ALL
  SELECT co.oid,'pg_conversion'::regclass,
         co.conname as name, n.nspname as namespace, 
         pg_get_userbyid(co.conowner) as owner,
         'CONVERSION' as sql_kind,
         format('%s%I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',co.conname) 
           as sql_identifier,
         null as acl
    FROM pg_conversion co JOIN pg_namespace n ON n.oid=co.connamespace
   WHERE $1 = 'pg_conversion'::regclass AND co.oid = $2
   UNION ALL
  SELECT lan.oid,'pg_language'::regclass,
         lan.lanname as name, null as namespace, 
         pg_get_userbyid(lan.lanowner) as owner,
         'LANGUAGE' as sql_kind,
         quote_ident(lan.lanname) as sql_identifier,
         lan.lanacl as acl
    FROM pg_language lan
   WHERE $1 = 'pg_language'::regclass AND lan.oid = $2
   UNION ALL
  SELECT opf.oid,'pg_opfamily'::regclass,
         opf.opfname as name, n.nspname as namespace, 
         pg_get_userbyid(opf.opfowner) as owner,
         'OPERATOR FAMILY' as sql_kind,
         format('%s%I USING %I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',
           opf.opfname,
           am.amname) 
           as sql_identifier,
         null as acl
    FROM pg_opfamily opf JOIN pg_namespace n ON n.oid=opf.opfnamespace
    JOIN pg_am am on (am.oid=opf.opfmethod)
   WHERE $1 = 'pg_opfamily'::regclass AND opf.oid = $2
   UNION ALL
  SELECT dat.oid,'pg_database'::regclass,
         dat.datname as name, null as namespace, 
         pg_get_userbyid(dat.datdba) as owner,
         'DATABASE' as sql_kind,
         quote_ident(dat.datname) as sql_identifier,
         dat.datacl as acl
    FROM pg_database dat
   WHERE $1 = 'pg_database'::regclass AND dat.oid = $2
   UNION ALL
  SELECT spc.oid,'pg_tablespace'::regclass,
         spc.spcname as name, null as namespace, 
         pg_get_userbyid(spc.spcowner) as owner,
         'TABLESPACE' as sql_kind,
         quote_ident(spc.spcname) as sql_identifier,
         spc.spcacl as acl
    FROM pg_tablespace spc
   WHERE $1 = 'pg_tablespace'::regclass AND spc.oid = $2
   UNION ALL
  SELECT opc.oid,'pg_opclass'::regclass,
         opcname as name, n.nspname as namespace, 
         pg_get_userbyid(opc.opcowner) as owner,
         'OPERATOR CLASS' as sql_kind,
         format('%s%I USING %I',
           quote_ident(nullif(n.nspname,current_schema()))||'.',
           opc.opcname,
           am.amname) 
           as sql_identifier,
         null as acl
    FROM pg_opclass opc JOIN pg_namespace n ON n.oid=opc.opcnamespace
    JOIN pg_am am ON am.oid=opc.opcmethod
   WHERE $1 = 'pg_opclass'::regclass AND opc.oid = $2
   UNION ALL
  SELECT e.oid, 'pg_extension'::regclass,
         e.extname AS name, n.nspname AS namespace, 
         pg_get_userbyid(e.extowner) AS owner,
         'EXTENSION'::text AS sql_kind,
         quote_ident(e.extname) AS sql_identifier,
         NULL::aclitem[] AS acl
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
   WHERE $1 = 'pg_extension'::regclass AND e.oid = $2   
#if 9.3
   UNION ALL
  SELECT evt.oid,'pg_event_trigger'::regclass,
         evt.evtname as name, null as namespace, 
         pg_get_userbyid(evt.evtowner) as owner,
         'EVENT TRIGGER' as sql_kind,
         quote_ident(evt.evtname) as sql_identifier,
         null as acl
    FROM pg_event_trigger evt
   WHERE $1 = 'pg_event_trigger'::regclass AND evt.oid = $2
   UNION ALL
  SELECT amproc.oid,'pg_amproc'::regclass,
         'FUNCTION '||amprocnum, null as namespace, null as owner,
         'AMPROC' as sql_kind,
         format('FUNCTION %s (%s)',
          amprocnum,
          array_to_string(array[amproclefttype,amprocrighttype]::regtype[],','))
         as sql_identifier,
         null as acl
    FROM pg_amproc amproc
   WHERE $1 = 'pg_amproc'::regclass AND amproc.oid = $2
   UNION ALL
  SELECT amop.oid,'pg_amop'::regclass,
         'OPERATOR '||amopstrategy, null as namespace, null as owner,
         'AMOP' as sql_kind,
         format('OPERATOR %s (%s)',
          amopstrategy,
          array_to_string(array[amoplefttype,amoprighttype]::regtype[],','))
         as sql_identifier,
         null as acl
    FROM pg_amop amop
   WHERE $1 = 'pg_amop'::regclass AND amop.oid = $2
#if 9.5
   UNION ALL
  SELECT pol.oid,'pg_policy'::regclass,
         pol.polname as name, null as namespace, null as owner,
         'POLICY' as sql_kind,
         format('%I ON %s',
                  polname,
                  cast(c.oid::regclass as text)) 
         as sql_identifier,
         null as acl
    FROM pg_policy pol JOIN pg_class c on (c.oid=pol.polrelid)
   WHERE $1 = 'pg_policy'::regclass AND pol.oid = $2
   UNION ALL
  SELECT trf.oid,'pg_transform'::regclass,
         null as name, null as namespace, null as owner,
         'TRANSFORM' as sql_kind,
         format('FOR %s LANGUAGE %I',
                  format_type(trf.trftype,null),
                  l.lanname) as sql_identifier,
         null as acl
    FROM pg_transform trf JOIN pg_language l on (l.oid=trf.trflang)
   WHERE $1 = 'pg_transform'::regclass AND trf.oid = $2
   UNION ALL
  SELECT am.oid,'pg_am'::regclass,
         am.amname as name, NULL as namespace, NULL as owner,
         'ACCESS METHOD' as sql_kind,
         quote_ident(amname) as sql_identifier,
         null as acl
    FROM pg_am am
   WHERE $1 = 'pg_am'::regclass AND am.oid = $2
#if 10
   UNION ALL
  SELECT stx.oid,'pg_statistic_ext'::regclass,
         stx.stxname, n.nspname as namespace, 
         pg_get_userbyid(stx.stxowner) as owner,
         'STATISTICS' as sql_kind,
         format('%s%I',quote_ident(nullif(n.nspname,current_schema()))
           ||'.',stx.stxname) 
           as sql_identifier,
         null as acl
    FROM pg_statistic_ext stx join pg_namespace n on (n.oid=stxnamespace)
   WHERE $1 = 'pg_statistic_ext'::regclass AND stx.oid = $2
   UNION ALL
  SELECT pub.oid,'pg_publication'::regclass,
         pub.pubname, NULL as namespace, 
         pg_get_userbyid(pub.pubowner) as owner,
         'PUBLICATION' as sql_kind,
         quote_ident(pub.pubname) as sql_identifier,
         null as acl
    FROM pg_publication pub
   WHERE $1 = 'pg_publication'::regclass AND pub.oid = $2
#if 14
   UNION ALL
  SELECT sub.oid,'pg_subscription'::regclass,
         sub.subname, NULL as namespace, 
         pg_get_userbyid(sub.subowner) as owner,
         'SUBSCRIPTION' as sql_kind,
         quote_ident(sub.subname) as sql_identifier,
         null as acl
    FROM pg_subscription sub
   WHERE $1 = 'pg_subscription'::regclass AND sub.oid = $2
#end
$$  strict;
COMMENT ON FUNCTION ddlx_identify(regclass,oid) 
     IS 'Identify an object by catalog and object id (exact)';

-- All objects with the given oid, one row per catalog, in priority order.
-- Duplicate oids occur only among some system objects; for user defined 
-- objects this normally returns a single row.
CREATE OR REPLACE FUNCTION ddlx_identify(
  IN oid,  
  OUT oid oid, OUT classid regclass, 
  OUT name name,  OUT namespace name,  
  OUT owner name, OUT sql_kind text, 
  OUT sql_identifier text, OUT acl aclitem[])
 RETURNS SETOF record LANGUAGE sql STABLE ROWS 1 AS $$
  SELECT i.oid, i.classid, i.name, i.namespace, i.owner, 
         i.sql_kind, i.sql_identifier, i.acl
    FROM unnest(array[
              'pg_class'
             ,'pg_proc'
             ,'pg_type'
             ,'pg_roles'
             ,'pg_rewrite'
             ,'pg_namespace'
             ,'pg_constraint'
             ,'pg_trigger'
             ,'pg_attrdef'
             ,'pg_operator'
             ,'pg_ts_config'
             ,'pg_ts_dict'
             ,'pg_ts_parser'
             ,'pg_ts_template'
             ,'pg_foreign_data_wrapper'
             ,'pg_foreign_server'
             ,'pg_user_mapping'
             ,'pg_cast'
             ,'pg_default_acl'
             ,'pg_collation'
             ,'pg_conversion'
             ,'pg_language'
             ,'pg_opfamily'
             ,'pg_database'
             ,'pg_tablespace'
             ,'pg_opclass'
             ,'pg_extension'
#if 9.3
             ,'pg_event_trigger'
             ,'pg_amproc'
             ,'pg_amop'
#if 9.5
             ,'pg_policy'
             ,'pg_transform'
             ,'pg_am'
#if 10
             ,'pg_statistic_ext'
             ,'pg_publication'
#if 14
             ,'pg_subscription'
#end
         ]::regclass[]) WITH ORDINALITY AS c(cls,n),
         LATERAL ddlx_identify(c.cls, $1) AS i
   WHERE i.oid IS NOT NULL
   ORDER BY c.n
$$  strict;
COMMENT ON FUNCTION ddlx_identify(oid) 
     IS 'Identify any object by object id (all matches, in priority order)';

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_describe(
  IN regclass, IN text[] default '{}',
  OUT ord smallint,
  OUT name name, OUT type text, OUT size integer, OUT not_null boolean,
  OUT "default" text,
  OUT ident text, OUT gen text,
  OUT comment text, OUT primary_key name,
  OUT is_local boolean, OUT storage text, OUT collation text, 
  OUT namespace name, OUT class_name name, OUT sql_identifier text,
  OUT relid oid, OUT options text[], OUT definition text,
  OUT sequence regclass,
  OUT compression text)
 RETURNS SETOF record LANGUAGE sql STABLE AS $$
SELECT  DISTINCT 
        a.attnum AS ord,
        a.attname AS name, 
        format_type(t.oid, NULL::integer) AS type,
        CASE
            WHEN (a.atttypmod - 4) > 0 THEN a.atttypmod - 4
            ELSE NULL::integer
        END AS size,
        a.attnotnull AS not_null,
        pg_get_expr(def.adbin,def.adrelid) AS "default",
#if 10
  nullif(a.attidentity::text,''),
#else
  null::text,
#end
#if 12
  nullif(a.attgenerated::text,''),
#else
  null::text,
#end
        col_description(c.oid, a.attnum::integer) AS comment,
        con.conname AS primary_key,
        a.attislocal AS is_local,
        case when a.attstorage<>t.typstorage
        then case a.attstorage
             when 'p' then 'plain'::text
             when 'e' then 'external'::text
             when 'm' then 'main'::text
             when 'x' then 'extended'::text
             else a.attstorage::text
             end
        end as storage,
        CASE WHEN a.attcollation <> t.typcollation THEN (select format('%I.%I',cn.nspname,col.collname) from pg_namespace cn where cn.oid = col.collnamespace) END AS collation,
        s.nspname AS namespace,
        c.relname AS class_name,
        format('%s.%I',text(c.oid::regclass),a.attname) AS sql_identifier,
        c.oid as relid,
#if 9.2
        attoptions||attfdwoptions as options,
#else
        attoptions as options,
#end
  format('%I %s%s%s%s%s%s%s',a.attname::text,format_type(t.oid, a.atttypmod),
#if 9.2
         case
           when a.attfdwoptions is not null
           then (
             select ' OPTIONS ( '||string_agg(
                quote_ident(option_name)||' '||quote_nullable(option_value), 
                ', ')||' ) '
               from pg_options_to_table(a.attfdwoptions))
         end,
#else
         null::text,
#end
         CASE
           WHEN a.attcollation <> t.typcollation
           THEN ' COLLATE ' || (select format('%I.%I',cn.nspname,col.collname) from pg_namespace cn where cn.oid = col.collnamespace)
         END
   ,
#if 10	
   case when a.attnotnull and attidentity not in ('a','d') then ' NOT NULL' end
#else
   case when a.attnotnull THEN ' NOT NULL' end
#end
   ,
   case when 'lite' ilike any($2) 
#if 12
        and a.attgenerated = ''
#end
        then ' DEFAULT ' || pg_get_expr(def.adbin,def.adrelid) end,
#if 10
  case when attidentity in ('a','d')
       then format(' GENERATED %s AS IDENTITY',
         case attidentity
         when 'a' then 'ALWAYS'
         when 'd' then 'BY DEFAULT'
         end)
       end
#else
   null::text
#end
  ,
#if 12
  case when a.attgenerated = 's'
       then format(' GENERATED ALWAYS AS (%s) STORED', 
                  pg_get_expr(def.adbin,def.adrelid))
       when a.attgenerated = 'v'
       then format(' GENERATED ALWAYS AS (%s)', 
                  pg_get_expr(def.adbin,def.adrelid))
  end
#else
         null::text
#end
   )
        AS definition,
        pg_get_serial_sequence(c.oid::regclass::text,a.attname)::regclass
	as sequence,
#if 14
        nullif(case a.attcompression 
               when 'l' then 'LZ4'
               when 'p' then 'PGLZ'
               else a.attcompression::text
               end,'')
#else
        null
#end
        AS compression
   FROM pg_class c
   JOIN pg_namespace s ON s.oid = c.relnamespace
   JOIN pg_attribute a ON c.oid = a.attrelid
   LEFT JOIN pg_attrdef def ON c.oid = def.adrelid AND a.attnum = def.adnum
   LEFT JOIN pg_constraint con
     ON con.conrelid = c.oid
        AND (a.attnum = ANY (con.conkey)) AND con.contype = 'p'
   LEFT JOIN pg_type t ON t.oid = a.atttypid
   LEFT JOIN pg_collation col ON col.oid = a.attcollation
   JOIN pg_namespace tn ON tn.oid = t.typnamespace
   LEFT JOIN pg_depend d ON def.oid = d.objid AND d.deptype='n'
   LEFT JOIN pg_class seq ON seq.oid = d.refobjid AND seq.relkind='S'
  WHERE c.relkind IN ('r','v','c','f','p')
        AND a.attnum > 0 AND NOT a.attisdropped
    AND has_table_privilege(c.oid, 'select') AND has_schema_privilege(s.oid, 'usage')
    AND c.oid = $1
  ORDER BY s.nspname, c.relname, a.attnum;
$$ strict;
COMMENT ON FUNCTION ddlx_describe(regclass, text[]) IS 'Describe columns of a class';

--------------------------------------------------------------- ---------------

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
 OUT oid oid,
 OUT is_local boolean)
 RETURNS SETOF record LANGUAGE sql STABLE AS $$
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
            when 'n'::"char" then 'NOT NULL'::text
            else c.contype::text
        end,
        pg_get_constraintdef(c.oid,true) AS constraint_definition,
        c.condeferrable AS is_deferrable, 
        c.condeferred  AS initially_deferred, 
        r.oid as regclass, c.oid AS sysid,
  d.refobjid is null AS is_local
   FROM pg_constraint c
   JOIN pg_class r ON c.conrelid = r.oid
   JOIN pg_namespace nc ON nc.oid = c.connamespace
   JOIN pg_namespace nr ON nr.oid = r.relnamespace
   LEFT JOIN pg_depend d ON d.objid = c.oid AND d.deptype='P'
  WHERE $1 IS NULL OR r.oid=$1
$$;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_get_rules(
  regclass default null,
  OUT namespace text, OUT class_name text, OUT rule_name text, OUT rule_event text, 
  OUT is_instead boolean, OUT rule_definition text, OUT regclass regclass)
 RETURNS SETOF record LANGUAGE sql STABLE AS $$
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
  WHERE ($1 IS NULL OR c.oid=$1)
    AND NOT (r.ev_type = '1'::"char" AND r.rulename = '_RETURN'::name)
  ORDER BY r.oid
  $$;
  
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_get_triggers(
  regclass default null,
  OUT oid oid,
  OUT is_constraint text, OUT trigger_name text, OUT action_order text, 
  OUT event_manipulation text, OUT event_object_sql_identifier text, 
  OUT action_statement text, OUT action_orientation text,
  OUT trigger_definition text, OUT regclass regclass,
  OUT regprocedure regprocedure, 
  OUT event_object_schema text, OUT event_object_table text,
  OUT sql_identifier text)
 RETURNS SETOF record LANGUAGE sql STABLE AS $$
 SELECT t.oid,
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
          case when (t.tgtype::integer &  4) <> 0 then 'INSERT'   end,
          case when (t.tgtype::integer &  8) <> 0 then 'DELETE'   end,
          case when (t.tgtype::integer & 16) <> 0 then 'UPDATE'   end,
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
        (quote_ident(t.tgname::text) || ' ON ') || c.oid::regclass::text 
          AS sql_identifier
   FROM pg_trigger t
   LEFT JOIN pg_class c ON c.oid = t.tgrelid
   LEFT JOIN pg_namespace s ON s.oid = c.relnamespace
   LEFT JOIN pg_proc p ON p.oid = t.tgfoid
   LEFT JOIN pg_namespace s1 ON s1.oid = p.pronamespace
   WHERE $1 IS NULL OR c.oid=$1
$$;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_get_indexes(
  regclass default null,
  OUT oid oid, OUT namespace text, OUT class regclass, OUT name text, 
  OUT tablespace text, OUT constraint_name text, OUT is_local boolean, 
  OUT is_clustered boolean)
 RETURNS SETOF record LANGUAGE sql STABLE AS $$
 SELECT DISTINCT
        i.oid AS oid, 
        n.nspname::text AS namespace, 
        c.oid AS class, 
        i.relname::text AS name,
        NULL::text AS tablespace, 
        cc.conname::text AS constraint_name,
        d2.refobjid IS NULL AS is_local,
        x.indisclustered as is_clustered
   FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_namespace n ON n.oid = c.relnamespace
   JOIN pg_class i ON i.oid = x.indexrelid
   JOIN pg_depend d ON d.objid = x.indexrelid
   LEFT JOIN pg_depend d2 ON d2.objid = x.indexrelid
        AND d2.deptype='P' AND d2.refclassid='pg_class'::regclass
   LEFT JOIN pg_constraint cc
        ON cc.oid = d.refobjid AND d.refclassid='pg_constraint'::regclass
  WHERE c.relkind in ('r','m','p')
    AND i.relkind in ('i','I')
    AND d.deptype in ('i','a')
    AND ($1 IS NULL OR c.oid = $1)
$$;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_get_functions(
  regproc default null,
  OUT oid oid, OUT namespace name, OUT name name, OUT comment text, 
  OUT owner name, OUT sql_identifier text, OUT language name,
  OUT attributes text,
  OUT retset boolean, OUT is_trigger boolean,
  OUT returns text,
  OUT arguments text, 
  OUT definition text, OUT security text, OUT is_strict text,
  OUT argtypes oidvector,
  OUT cost real, OUT rows real)
 RETURNS SETOF record LANGUAGE sql STABLE AS $$
 SELECT p.oid AS oid, 
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
   WHERE $1 IS NULL OR p.oid = $1
$$;

--------------------------------------------------------------- ---------------
--  DDL generator functions for individial object types  --
--------------------------------------------------------------- ---------------

-- Makes text safe for use inside a "--" comment: CR and LF would end the
-- comment and let the rest of the name run as SQL, so they are written as \r and \n
CREATE OR REPLACE FUNCTION ddlx_comment_text(text)
 RETURNS text LANGUAGE sql IMMUTABLE AS $$
  select replace(replace($1, E'\r', E'\\r'), E'\n', E'\\n')
$$ strict;

-- Comments out SQL text line by line, however many lines it has. Unlike /* */
-- this cannot be closed early by a "*/" inside a quoted name or a function body.
CREATE OR REPLACE FUNCTION ddlx_comment_out(text)
 RETURNS text LANGUAGE sql IMMUTABLE AS $$
  select '-- ' || regexp_replace(rtrim($1, E'\r\n'), E'(\r\n|\r|\n)', E'\\1-- ', 'g') || E'\n'
$$ strict;

CREATE OR REPLACE FUNCTION ddlx_banner(
   name text, kind text, namespace text, owner text, extra text default null
 )
 RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format(E'\n%s-- Type: %s ; Name: %s; Owner: %s\n\n',
                E'--\n-- ' || ddlx_comment_text($5) || E'\n',
                ddlx_comment_text($2),ddlx_comment_text($1),ddlx_comment_text($4))
$$;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_comment(regclass, oid, text[])
 RETURNS text LANGUAGE sql STABLE AS $$
 select case when comment is not null or 'comments' ilike any($3)
        then format(
          E'COMMENT ON %s %s IS %L;\n',
    sql_kind, sql_identifier, comment
        ) else ''
  end
   from (
   select obj.sql_kind, sql_identifier, 
          case 
            when obj.classid='pg_database'::regclass
            then shobj_description(oid,classid::name)
            when obj.classid='pg_tablespace'::regclass
            then shobj_description(oid,classid::name)
            -- role comments are emitted by ddlx_alter_role
            when obj.classid='pg_roles'::regclass then null
#if 10
            -- subscriptions are shared objects too (no comment lookup here)
            when obj.classid='pg_subscription'::regclass then null
#end
            else obj_description(oid,classid::name)
          end as comment
     from ddlx_identify($1,$2) as obj
   ) as c
$$ strict;
COMMENT ON FUNCTION ddlx_comment(regclass, oid, text[]) 
     IS 'Get SQL COMMENT statement for an object by catalog and object id (exact)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_comment(oid, text[] default '{comments}')
 RETURNS text LANGUAGE sql STABLE AS $w$
  select ddlx_comment(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$w$ strict;

#if 9.1
--------------------------------------------------------------- ---------------

-- SECURITY LABEL statements for an object and, for classes, its columns.
-- Labels of roles, databases, tablespaces and subscriptions live in the shared
-- catalog pg_shseclabel, all others in pg_seclabel (matched by class as well as oid).
CREATE OR REPLACE FUNCTION ddlx_security_label(regclass, oid, text[])
 RETURNS text LANGUAGE sql STABLE AS $$
 with obj as (select * from ddlx_identify($1,$2)),
 l as (
  select s.provider, s.label, s.objsubid,
         case when s.objsubid > 0 then 'COLUMN' else obj.sql_kind end as kind,
         case when s.objsubid > 0
              then format('%s.%I', obj.sql_identifier,
                          (select a.attname from pg_attribute a
                            where a.attrelid = obj.oid and a.attnum = s.objsubid))
              else obj.sql_identifier
         end as ident
    from obj
    join pg_seclabel s on s.objoid = obj.oid and s.classoid = obj.classid
  union all
  select s.provider, s.label, 0, obj.sql_kind, obj.sql_identifier
    from obj
    join pg_shseclabel s
      on s.objoid = obj.oid
     and s.classoid = case when obj.classid = 'pg_roles'::regclass
                           then 'pg_authid'::regclass else obj.classid end
 )
 select case when 'lite' ilike any($3) or 'nolabels' ilike any($3) then ''
        else coalesce(string_agg(
               format(E'SECURITY LABEL FOR %I ON %s %s IS %L;\n',
                      provider, kind, ident, label),
               '' order by provider, objsubid), '')
        end
   from l
$$ strict;
COMMENT ON FUNCTION ddlx_security_label(regclass, oid, text[]) 
     IS 'Get SECURITY LABEL statements for an object by catalog and object id (exact)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_security_label(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $w$
  select ddlx_security_label(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$w$ strict;
#end

--------------------------------------------------------------- ---------------
-- forward declarations, will be redefined later
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create(oid, text[] default '{}') 
  RETURNS text LANGUAGE sql STABLE AS $$ select null::text $$;

CREATE OR REPLACE FUNCTION ddlx_create_function(regproc, text[] default '{}') 
  RETURNS text LANGUAGE sql STABLE AS $$ select null::text $$;

CREATE OR REPLACE FUNCTION ddlx_data_backup(regclass, text[] default '{}') 
  RETURNS text LANGUAGE sql STABLE AS $$ select null::text $$;

CREATE OR REPLACE FUNCTION ddlx_data_restore(regclass, text[] default '{}') 
  RETURNS text LANGUAGE sql STABLE AS $$ select null::text $$;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_alter_owner(regclass, oid, text[])
 RETURNS text LANGUAGE sql STABLE AS $$
 select case when 'nodcl' ilike any($3) 
               or 'noowner' ilike any($3) or 'lite' ilike any($3) 
             then null
        else case 
          when 'owner' ilike any($3) or obj.owner is distinct from current_role
          then
          case obj.sql_kind
           when 'INDEX' then null
           when 'EXTENSION' then null
           when 'DEFAULT PRIVILEGES' then null   -- belongs to the role named in the statement
           else 'ALTER '||sql_kind||' '||sql_identifier||
                 ' OWNER TO '||quote_ident(owner)||E';\n'
          end end
        end
  from ddlx_identify($1,$2) obj 
$$  strict;
COMMENT ON FUNCTION ddlx_alter_owner(regclass, oid, text[]) 
     IS 'Get SQL ALTER OWNER statement for an object by catalog and object id (exact)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_alter_owner(oid, text[] default '{owner}')
 RETURNS text LANGUAGE sql STABLE AS $w$
  select ddlx_alter_owner(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$w$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_table(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
  with obj as (select * from ddlx_identify('pg_class'::regclass,$1))
  select   
    array_to_string(array[
      'CREATE '||
      case relpersistence
        when 'u' then 'UNLOGGED '
        when 't' then 'TEMPORARY '
        else ''
      end
      || obj.sql_kind || ' ' 
      || case when 'ine' ilike any($2) then 'IF NOT EXISTS ' else '' end
      || obj.sql_identifier
      || case when reloftype>0 then ' OF '||cast(reloftype::regtype as text) else '' end
      || case obj.sql_kind when 'TYPE' then ' AS' else '' end 
      ||
#if 10
  case
  when c.relispartition
  then ' PARTITION OF ' || (SELECT string_agg(i.inhparent::regclass::text,',')
                             FROM pg_inherits i WHERE i.inhrelid = $1) 
  else
#end
    case when reloftype>0
    then ''
    else
    ' (' ||coalesce(E'\n' ||
      array_to_string(array_cat(
        (SELECT array_agg('    '||definition) FROM ddlx_describe($1,$2) WHERE is_local),
        case when 'lite' ilike any($2)
              and not 'noconstraints' ilike any($2) 
             then (SELECT array_agg('    '||sql) FROM (
                   select 'CONSTRAINT ' || quote_ident(constraint_name) || 
                          ' ' || constraint_definition as sql
                     from ddlx_get_constraints($1) 
                    where is_local and constraint_type <> 'NOT NULL'
	      order by constraint_type desc, constraint_name) as a)
        end
      ), E',\n') || E'\n','') || '  )'
    end
#if 10
  end
#end
#if 10
  ,
  case when c.relpartbound is not null
       then pg_get_expr(c.relpartbound,c.oid,true)
  end
#end
  ,
#if 10
  case
  when not c.relispartition
  then (SELECT 'INHERITS(' || string_agg(i.inhparent::regclass::text,', ') || E')'
          FROM pg_inherits i WHERE i.inhrelid = $1)
  end
#else
  (SELECT 'INHERITS(' || string_agg(i.inhparent::regclass::text,', ') || E')'
     FROM pg_inherits i WHERE i.inhrelid = $1) 
#end
#if 10
  ,
  CASE 
  WHEN p.partstrat IS NOT NULL
  THEN 'PARTITION BY ' || pg_get_partkeydef($1)
  END
#end
#if 12
  ,
  -- Table access method (PG12+). heap is the default unless default_table_access_method
  -- was changed, in which case it has to be spelled out as well.
  CASE 
  WHEN c.relam <> 0 AND NOT 'lite' ILIKE ANY($2)
   AND (am.amname <> 'heap' OR current_setting('default_table_access_method') <> 'heap')
  THEN 'USING ' || quote_ident(am.amname)
  END
#end
#unless 12
  ,
  CASE relhasoids WHEN true THEN 'WITH OIDS' END
#end
  ,
    case when fs.srvname is not null
    then E'SERVER '||quote_ident(fs.srvname)||
         coalesce(E' OPTIONS (\n'||
           (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value), 
              E',\n')
              from pg_options_to_table(ft.ftoptions))||E'\n)','')
    end
    

  ],E'\n  ')
  ||
  E';\n'
 FROM pg_class c JOIN obj ON (true)
 LEFT JOIN pg_foreign_table  ft ON (c.oid = ft.ftrelid)
 LEFT JOIN pg_foreign_server fs ON (ft.ftserver = fs.oid)
#if 12
 LEFT JOIN pg_am am ON am.oid = c.relam
#end
#if 10
 LEFT JOIN pg_partitioned_table p ON p.partrelid = c.oid
#end
 WHERE c.oid = $1
-- AND relkind in ('r','c')
$$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_view(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
 select 
 'CREATE '||
  case relkind 
    when 'v' THEN case when 'lite' ilike any($2) then '' else 'OR REPLACE ' end || 'VIEW '
    when 'm' THEN 'MATERIALIZED VIEW ' ||
      case when 'ine' ilike any($2) then 'IF NOT EXISTS ' else '' end
  end || (oid::regclass::text) ||
#if 12
  coalesce(
    (select ' USING ' || quote_ident(am.amname) from pg_am am
      where am.oid = t.relam and t.relkind = 'm' and not 'lite' ilike any($2)
        and (am.amname <> 'heap' or current_setting('default_table_access_method') <> 'heap')),
    '') ||
#end
  E' AS\n' ||
  trim(';' from pg_catalog.pg_get_viewdef(oid,true)) ||
#if 9.3
  case when relkind='m' and not relispopulated
       then E'\n  WITH NO DATA'
       else E''
  end ||
#end
  E';\n'
 FROM pg_class t
 WHERE oid = $1
   AND relkind in ('v','m')
$$  strict;

--------------------------------------------------------------- ---------------

-- ALTER SEQUENCE with all parameters. With the 'data' or 'setval' option the current
-- value is restored as well (only if nextval was ever called).
CREATE OR REPLACE FUNCTION ddlx_alter_sequence(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 with obj as (select * from ddlx_identify('pg_class'::regclass,$1))
#if 10
 select 
    'ALTER SEQUENCE '||(obj.oid::regclass::text) 
 ||E'\n INCREMENT BY '||s.seqincrement
 ||E'\n MINVALUE '||s.seqmin
 ||E'\n MAXVALUE '||s.seqmax
 ||E'\n START WITH '||s.seqstart
 -- identity sequences are created with defaults: bring the current value to the start
 ||case when 'restart' ilike any($2) then E'\n RESTART WITH '||s.seqstart else '' end
 ||E'\n CACHE '||s.seqcache
 ||E'\n '|| case when s.seqcycle then 'CYCLE' else 'NO CYCLE' end
 ||E';\n'
 || case when ('data' ilike any($2) or 'setval' ilike any($2))
          and pg_sequence_last_value($1) is not null
         then format(E'SELECT pg_catalog.setval(%L, %s, true);\n',
                     obj.oid::regclass::text, pg_sequence_last_value($1))
         else '' end
 FROM pg_sequence s JOIN obj ON (obj.oid = s.seqrelid)
 WHERE obj.sql_kind = 'SEQUENCE'
#else
 select 
    'ALTER SEQUENCE '||(oid::regclass::text) 
 ||E'\n INCREMENT BY '||increment
 ||E'\n MINVALUE '||minimum_value
 ||E'\n MAXVALUE '||maximum_value
 ||E'\n START WITH '||start_value
 ||E'\n '|| case cycle_option when 'YES' then 'CYCLE' else 'NO CYCLE' end
 ||E';\n'
 FROM information_schema.sequences s JOIN obj ON (true)
 WHERE sequence_schema = obj.namespace
   AND sequence_name = obj.name
   AND obj.sql_kind = 'SEQUENCE'
#end
$function$  strict;

CREATE OR REPLACE FUNCTION ddlx_drop_sequence(regclass)
 RETURNS text LANGUAGE sql STABLE AS $$
  with seq as (
  select sc.oid::regclass,d.refobjid::regclass,
         a.attrelid,a.attname,
#if 10
         a.attidentity
#else
         ''
#end
    from pg_class sc
    left join pg_depend d on d.objid = sc.oid and d.deptype in ('a','i')
    left join pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
   where relkind='S' and sc.oid = $1
 )
#if 10
 select case 
        when attidentity in ('d','a')
        then format(e'ALTER TABLE %s ALTER %I DROP IDENTITY;\n',attrelid::regclass,attname)
        else format(e'DROP SEQUENCE IF EXISTS %s;\n',$1::text)
        end
#else
 select format(e'DROP SEQUENCE IF EXISTS %s;\n',$1::text)
#end
   from seq
$$  strict;

#if 10
-- The parameters of CREATE SEQUENCE that differ from what the bare statement would give.
-- ALTER SEQUENCE ... START WITH does not move the current value, and a MINVALUE above the
-- initial value of 1 is refused, so the parameters have to be part of CREATE.
CREATE OR REPLACE FUNCTION ddlx_sequence_options(regclass)
 RETURNS text LANGUAGE sql STABLE AS $$
 with s as (
  select ps.*,
         case ps.seqtypid when 'smallint'::regtype then 32767::bigint
                          when 'integer'::regtype  then 2147483647::bigint
                          else 9223372036854775807::bigint end as typemax,
         ps.seqincrement > 0 as asc_
    from pg_sequence ps where ps.seqrelid = $1
 ),
 d as (
  select s.*,
         case when asc_ then 1 else -s.typemax - 1 end as def_min,
         case when asc_ then s.typemax else -1 end as def_max
    from s
 )
 select coalesce(array_to_string(array[
          case when seqincrement <> 1 then E'\n  INCREMENT BY ' || seqincrement end,
          case when seqmin <> def_min then E'\n  MINVALUE ' || seqmin end,
          case when seqmax <> def_max then E'\n  MAXVALUE ' || seqmax end,
          case when seqstart <> case when asc_ then def_min else def_max end
               then E'\n  START WITH ' || seqstart end,
          case when seqcache <> 1 then E'\n  CACHE ' || seqcache end,
          case when seqcycle then E'\n  CYCLE' end
        ], ''), '')
   from d
$$ strict;
#end

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_sequence(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
  with seq as (
  select sc.oid::regclass,d.refobjid::regclass,
         a.attrelid,a.attname,
#if 10
         a.attidentity, ps.seqtypid
#else
         '', null::oid
#end
    from pg_class sc
#if 10
    left join pg_sequence ps on ps.seqrelid = sc.oid
#end
    left join pg_depend d on d.objid = sc.oid and d.deptype in ('a','i')
    left join pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
   where relkind='S' and sc.oid = $1
 )
#if 10
 select case 
        when attidentity in ('d','a')
        then format(e'ALTER TABLE %s ALTER %I ADD GENERATED %s AS IDENTITY;\n',
                      attrelid::regclass,attname,
                      case attidentity::text
                      when 'd' then 'BY DEFAULT'
                      when 'a' then 'ALWAYS'
                      else attidentity::text
                      end)
        else format(e'CREATE SEQUENCE %s%s%s%s;\n',
                    case when 'ine' ilike any($2) then 'IF NOT EXISTS ' end, 
                    $1::text,
                    case when seqtypid <> 'bigint'::regtype
                         then ' AS ' || format_type(seqtypid, null) end,
                    ddlx_sequence_options($1))
        end
#else
 select format(e'CREATE SEQUENCE %s%s;\n',
                    case when 'ine' ilike any($2) then 'IF NOT EXISTS ' end, 
                    $1::text)
#end
   from seq
$$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_type_shell(regtype)
 RETURNS text LANGUAGE sql STABLE AS $$
select format('CREATE TYPE ' || format_type(oid,null) || e';\n\n') ||
       (select string_agg(ddlx_create_function(u,'{compact}'),'')
         from unnest(array[t.typinput,t.typoutput,t.typsend,t.typreceive]) as u)
  from pg_type t
 where oid = $1
$$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_type_base(regtype, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
select case when 'script' ilike any($2) then ddlx_create_type_shell($1) else '' end ||
       'CREATE TYPE ' || format_type($1,null) || ' (' || E'\n  ' ||
       array_to_string(array[ 
         'INPUT = '  || cast(t.typinput::regproc as text),  
         'OUTPUT = ' || cast(t.typoutput::regproc as text),
         'SEND = ' || cast(nullif(t.typsend,0)::regproc as text), 
         'RECEIVE = ' || cast(nullif(t.typreceive,0)::regproc as text),
         'TYPMOD_IN = ' || cast(nullif(t.typmodin,0)::regproc as text),
         'TYPMOD_OUT = ' || cast(nullif(t.typmodout,0)::regproc as text),
         'ANALYZE = ' || cast(nullif(t.typanalyze,0)::regproc as text),
#if 14
         'SUBSCRIPT = ' || cast(nullif(t.typsubscript,0)::regproc as text),
#end
         'INTERNALLENGTH = ' || 
            case when  t.typlen < 0 then 'VARIABLE' else cast(t.typlen as text) end,
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
         'CATEGORY = ' || quote_nullable(t.typcategory::text),
         case when t.typispreferred then E'PREFERRED = true' end,
         case 
           when t.typdefault is not null 
           then E'DEFAULT = ' || quote_nullable(t.typdefault)
         end,
         case when t.typelem <> 0 then E'ELEMENT = ' || format_type(t.typelem,null) end,
         'DELIMITER = ' || quote_nullable(t.typdelim::text),
         'COLLATABLE = ' ||  case when t.typcollation <> 0 then 'true' else 'false' end
         ], E',\n  ')
       || E'\n);\n\n'
  from pg_type t
 where oid = $1
$$  strict;

--------------------------------------------------------------- ---------------

#if 9.2
CREATE OR REPLACE FUNCTION ddlx_create_type_range(regtype)
 RETURNS text  LANGUAGE sql STABLE AS $$
select 'CREATE TYPE ' || format_type($1,null) || E' AS RANGE (\n  ' ||
        array_to_string(array[
          'SUBTYPE = '  || format_type(r.rngsubtype,null),
          'SUBTYPE_OPCLASS = '  || quote_ident(opc.opcname),
          case
            when r.rngcollation <> 0
            then 'COLLATION = ' || (select format('%I.%I',cn.nspname,col.collname) from pg_namespace cn where cn.oid = col.collnamespace)
          end,
          'CANONICAL = ' || cast(nullif(r.rngcanonical,0)::regproc as text),          
          'SUBTYPE_DIFF = ' || cast(nullif(r.rngsubdiff,0)::regproc as text)
#if 14
          ,'MULTIRANGE_TYPE_NAME = ' || (r.rngmultitypid::regtype::text)
#if 9.2
        ],E',\n  ')
       || E'\n);\n\n'
  from pg_range r
  left join pg_opclass opc on (opc.oid=r.rngsubopc)
  left join pg_collation col on (col.oid=r.rngcollation)
 where r.rngtypid = $1
$$  strict;
#end
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_type_enum(regtype)
 RETURNS text LANGUAGE sql STABLE AS $$
with
ee as (
 select 
   quote_nullable(enumlabel) as label
   from pg_enum
  where enumtypid = $1
  order by enumsortorder
)
select 'CREATE TYPE ' || format_type($1,null) || ' AS ENUM (' || E'\n ' ||
       string_agg(label,E',\n ') || E'\n);\n\n'
  from ee
$$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_type_domain(regtype)
 RETURNS text LANGUAGE sql STABLE AS $$
with
cc as (
  select format('CONSTRAINT %I %s',conname,pg_get_constraintdef(oid)) as definition
    from pg_constraint con
   where con.contypid = $1
   order by oid
)
select 'CREATE DOMAIN ' || format_type(t.oid,null) 
       || E' AS ' || format_type(t.typbasetype,typtypmod) 
       || coalesce(E'\n  '||(select string_agg(definition,E'\n  ') from cc),'')
       -- before PG17 NOT NULL is only typnotnull; from PG17 it is a named constraint (in cc)
       || case
            when t.typnotnull
             and not exists (select 1 from pg_constraint n
                              where n.contypid = t.oid and n.contype = 'n')
            then E'\n  NOT NULL'
            else ''
          end
       || case
            when t.typcollation <> (select b.typcollation from pg_type b where b.oid = t.typbasetype)
            then E'\n  COLLATE ' || (select format('%I.%I',cn.nspname,col.collname) from pg_namespace cn where cn.oid = col.collnamespace)
            else ''
          end 
       || coalesce(E'\n  DEFAULT ' || t.typdefault, '')
       || E';\n\n'
  from pg_type t
  left join pg_collation col on (col.oid=t.typcollation)
 where t.oid = $1
$$  strict;

--------------------------------------------------------------- ---------------

-- pg_get_constraintdef only includes the index's WITH (...) and USING INDEX TABLESPACE
-- in its "full command" form, which is not available from SQL. The result is meant to be
-- appended to the definition of a primary key, unique or exclusion constraint.
CREATE OR REPLACE FUNCTION ddlx_constraint_index_storage(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 select coalesce((
   select coalesce(
            -- exclusion constraints already show their WITH (...) in the definition
            (select ' WITH (' || string_agg(quote_ident(o.option_name) || '=' ||
                                            quote_literal(o.option_value), ', '
                                            order by o.option_name) || ')'
               from pg_options_to_table(i.reloptions) o
              where c.contype in ('p','u')), '')
          ||
          coalesce((select ' USING INDEX TABLESPACE ' || quote_ident(t.spcname)
                      from pg_tablespace t where t.oid = i.reltablespace), '')
     from pg_constraint c
     join pg_class i on i.oid = c.conindid
    where c.oid = $1
      and c.contype in ('p','u','x')
      and not ('nostorage' ilike any($2) or 'lite' ilike any($2))
 ), '')
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_index(regclass,ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
 with ii as (
 SELECT CASE d.refclassid
            WHEN 'pg_constraint'::regclass 
            THEN 'ALTER TABLE ' || text(c.oid::regclass) 
                 || ' ADD CONSTRAINT ' || quote_ident(cc.conname) 
                 || ' ' || pg_get_constraintdef(cc.oid)
                 || ddlx_constraint_index_storage(cc.oid, $2)
            ELSE pg_get_indexdef(i.oid)
                 -- pg_get_indexdef leaves the tablespace out
                 || case when i.reltablespace <> 0
                          and not ('nostorage' ilike any($2) or 'lite' ilike any($2))
                         then ' TABLESPACE ' || quote_ident((select t.spcname from pg_tablespace t
                                                              where t.oid = i.reltablespace))
                         else '' end
        END
        AS indexdef,
        not coalesce(cc.conislocal,true) as commented
   FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_class i ON i.oid = x.indexrelid
   JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = x.indexrelid
   LEFT JOIN pg_constraint cc ON cc.oid = d.refobjid
  WHERE i.oid = $1
    -- AND c.relkind in ('r','m','p') AND i.relkind = 'i'::"char"  
)
 SELECT case 
        when commented then ddlx_comment_out(indexdef || ';')
        when 'ine' ilike any($2) 
        then regexp_replace(indexdef,'^CREATE ([\w ]*)?INDEX','CREATE \1INDEX IF NOT EXISTS') || E';\n'
        else indexdef || E';\n'
        end
   FROM ii
$$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_drop_index(regclass,ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
 with ii as (
 SELECT CASE d.refclassid
            WHEN 'pg_constraint'::regclass 
            THEN 'ALTER TABLE ' || text(c.oid::regclass) 
                 || ' DROP CONSTRAINT ' || quote_ident(cc.conname) 
            ELSE 'DROP INDEX ' || text(i.oid::regclass)
        END
        AS indexdef,
        not coalesce(cc.conislocal,true) as commented
   FROM pg_index x
   JOIN pg_class c ON c.oid = x.indrelid
   JOIN pg_class i ON i.oid = x.indexrelid
   JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = x.indexrelid
   LEFT JOIN pg_constraint cc ON cc.oid = d.refobjid
  WHERE i.oid = $1
    -- AND c.relkind in ('r','m','p') AND i.relkind = 'i'::"char"  
)
 SELECT case when commented
             then ddlx_comment_out(indexdef || ';')
             else indexdef || E';\n'
        end
   FROM ii
$$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_drop_trigger(oid,ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
select format(e'DROP TRIGGER %I ON %s;\n',
               tgname, tgrelid::text)
  from pg_trigger t
 where t.oid = $1
   and not ('script' ilike any($2) and t.tgisinternal)
$$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_class(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 with obj as (select * from ddlx_identify('pg_class'::regclass,$1)),

 comments as (
   select 'COMMENT ON COLUMN ' || text($1) || '.' || quote_ident(name) ||
          ' IS ' || quote_nullable(comment) || ';' as cc
     from ddlx_describe($1,$2) 
    where comment IS NOT NULL 
 ),

 settings as (
   select 'ALTER ' || obj.sql_kind || ' ' || text($1) || ' SET (' || 
          quote_ident(option_name)||'='||quote_nullable(option_value) ||');' as ss
     from pg_options_to_table((select reloptions from pg_class where oid = $1))
     join obj on (true)
 )

   select array_to_string(array[
          ddlx_banner(obj.name,obj.sql_kind,obj.namespace,obj.owner) 
          ,
          case 
            when obj.sql_kind in ('VIEW','MATERIALIZED VIEW') then ddlx_create_view($1,$2)  
            when obj.sql_kind in ('TABLE','TYPE','FOREIGN TABLE') then ddlx_create_table($1,$2)
            when obj.sql_kind in ('SEQUENCE') then ddlx_create_sequence($1,$2)
            when obj.sql_kind in ('INDEX') then ddlx_create_index($1,$2)
            else '-- UNSUPPORTED CLASS: '||obj.sql_kind
          end 
          ,
          case when 'nocomments' ilike any($2) then ''
               else coalesce((select string_agg(cc,E'\n')||E'\n' from comments),'')
          end
          ,
          coalesce(E'\n'||(select string_agg(ss,E'\n')||E'\n' from settings),'')
          ],'') || E'\n'

     from obj
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_alter_table_defaults(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
with
def as (
 select 
    coalesce(
      string_agg(
        format('ALTER TABLE %s ALTER %I SET DEFAULT %s;',
                text($1),name,"default"), 
        E'\n') || E'\n\n', 
    '') as ddl
   from ddlx_describe($1,$2)
  where "default" is not null
    and "sequence" is null and gen is null
),
seq as (
 select 
    coalesce(
      string_agg(
       case when 'script' ilike any($2)
            then format(e'CREATE SEQUENCE %s%s;\n%s',
#if 9.5
             'IF NOT EXISTS ',
#else
       '',
#end
                   "sequence",
       ddlx_alter_owner('pg_class'::regclass,"sequence",$2)
           ) else '' end ||
      format(e'ALTER SEQUENCE %s OWNED BY %s;',"sequence",sql_identifier),
  E'\n') || E'\n\n', '') as ddl
   from ddlx_describe($1,$2)
  where "sequence" is not null and ident is null
)
select case when 'lite' ilike any($2) then ''
            else array_to_string(array[def.ddl,seq.ddl],'') end
  from def,seq
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_alter_table_storage(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
with 
obj as (select * from ddlx_identify('pg_class'::regclass,$1)),
d as (select * from ddlx_describe($1,$2) order by name),
cs as (
  select 
    coalesce(
      string_agg(format(E'ALTER %s %s ALTER %I SET STORAGE %s;',
            obj.sql_kind,obj.sql_identifier,d.name,d.storage), E'\n') || E'\n\n', 
    '') as ddl
   from d, obj
  where d.storage is not null
),
lz as (
  select 
    coalesce(
      string_agg(format(E'ALTER %s %s ALTER %I SET COMPRESSION %s;',
            obj.sql_kind,obj.sql_identifier,d.name,d.compression), E'\n') || E'\n\n', 
    '') as ddl
   from d, obj
  where d.compression is not null
),
ts as (
  select case when s.oid is not null then
         format(E'ALTER %s %s SET TABLESPACE %I;\n\n',
                obj.sql_kind, obj.sql_identifier, s.spcname) 
         else '' end as ddl
    from obj, pg_class c 
    left join pg_tablespace s on (s.oid=c.reltablespace)
   where c.oid = $1
)
select cs.ddl || lz.ddl || ts.ddl
  from cs,ts,lz
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_alter_table_settings(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
with 
obj as (select * from ddlx_identify('pg_class'::regclass,$1)),
ob as (
 select coalesce(string_agg(a.ddl, E'\n') || E'\n\n', '')
        as ddl
 from (
 select format(E'ALTER %s %s ALTER %I SET ( %s = %s );',
           obj.sql_kind,obj.sql_identifier,att.attname,
           o.option_name, quote_nullable(o.option_value)) as ddl
   from pg_attribute att
   cross join lateral pg_options_to_table(att.attoptions) as o, obj
  where attnum>0 and att.attrelid=$1 and attoptions is not null and not attisdropped
    and o.option_name <> 'pg_attver'
  order by att.attname, o.option_name
 ) as a
),
os as (
 select coalesce(string_agg(a2.ddl, E'\n') || E'\n\n', '')
        as ddl
 from (
 select format(E'ALTER %s %s ALTER %I SET STATISTICS %s;',
           obj.sql_kind,obj.sql_identifier,att.attname,
           attstattarget) as ddl
   from pg_attribute att, obj
  where attnum>0 and att.attrelid=$1 and attstattarget>=0 and not attisdropped
  order by att.attname
 ) as a2
)
#if 10
,
-- the sequences behind identity columns carry the identity's start, increment, cache...
idseq as (
 select coalesce(string_agg(ddlx_alter_sequence(d.objid::regclass, $2 || '{restart}'::text[]), E'\n' order by a.attnum) || E'\n', '') as ddl
   from pg_depend d
   join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
  where d.classid = 'pg_class'::regclass and d.refclassid = 'pg_class'::regclass
    and d.refobjid = $1 and d.deptype = 'i' and a.attidentity <> ''
)
select ob.ddl || os.ddl || idseq.ddl
  from ob,os,idseq
#else
select ob.ddl || os.ddl
  from ob,os
#end
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_default(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
  select format(E'ALTER TABLE %s ALTER %I SET DEFAULT %s;\n',
            cast(c.oid::regclass as text),
            a.attname, 
            pg_get_expr(def.adbin,def.adrelid))
    from pg_attrdef def 
    join pg_class c on c.oid = def.adrelid
    join pg_attribute a on c.oid = a.attrelid and a.attnum = def.adnum and not a.attisdropped
   where def.oid = $1
#if 12 
     and a.attgenerated = ''
#end
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_drop_default(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
  select format(E'ALTER TABLE %s ALTER %I DROP %s;\n',
            cast(c.oid::regclass as text),
            a.attname,
#if 12
            case when a.attgenerated <> ''
                 then 'EXPRESSION' else 'DEFAULT' end
#else
            'DEFAULT'
#end
            )
    from pg_attrdef def 
    join pg_class c on c.oid = def.adrelid
    join pg_attribute a on c.oid = a.attrelid and a.attnum = def.adnum and not a.attisdropped
   where def.oid = $1
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_constraints(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 with cs as (
  select
   'ALTER TABLE ' || text(regclass(regclass)) ||  
   ' ADD CONSTRAINT ' || quote_ident(constraint_name) || 
   E' ' || constraint_definition || ddlx_constraint_index_storage(gc.oid, $2) as sql
    from ddlx_get_constraints($1) gc
    join pg_constraint co on (co.oid = gc.oid)
   where is_local
     and (constraint_type <> 'CHECK' or not 'script' ilike any($2))
     and (constraint_type <> 'NOT NULL')
     and (co.conrelid is distinct from co.confrelid or not 'script' ilike any($2))
   order by constraint_type desc, constraint_name
 )
 select coalesce(string_agg(sql,E';\n') || E';\n\n','')
   from cs
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_constraint(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 select case
        when not 'noconstraints' ilike any($2)
        then format(
          E'ALTER %s %s ADD CONSTRAINT %I\n      %s;\n',
          case when t.oid is not null then 'DOMAIN' else 'TABLE' end,
          coalesce(cast(t.oid::regtype as text),cast(r.oid::regclass as text)),
          c.conname, 
          pg_get_constraintdef(c.oid,true) || ddlx_constraint_index_storage(c.oid, $2))
  end
   from pg_constraint c 
   left join pg_class r on (c.conrelid = r.oid)
   left join pg_type t on (c.contypid = t.oid)
  where c.oid = $1 
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_drop_constraint(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
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
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_rules(regclass)
 RETURNS text LANGUAGE sql STABLE AS $function$
  select coalesce(string_agg(gr.rule_definition,E'\n')||E'\n\n','')
    from ddlx_get_rules($1) gr
    join pg_rewrite r on r.ev_class = $1 and r.rulename = gr.rule_name
   where gr.rule_definition is not null
     and r.ev_enabled <> 'D'   -- disabled rules are left out
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_rule(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
  select case
         when ev_type='1' and r.rulename='_RETURN'
         then ddlx_create_class(c.oid)
         else pg_get_ruledef(r.oid)
         end
    from pg_rewrite r join pg_class c on (c.oid=r.ev_class)
   where r.oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_trigger(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 select pg_get_triggerdef($1,true)||
        case t.tgenabled 
             when 'D' then format(E';\nALTER TABLE %s DISABLE TRIGGER %I',
                                  cast(t.tgrelid::regclass as text), t.tgname)
             when 'R' then format(E';\nALTER TABLE %s ENABLE REPLICA TRIGGER %I', 
                                  cast(t.tgrelid::regclass as text), t.tgname)
             when 'A' then format(E';\nALTER TABLE %s ENABLE ALWAYS TRIGGER %I', 
                                  cast(t.tgrelid::regclass as text), t.tgname)
             else ''
        end||E';\n'
   from pg_trigger t
  where oid = $1
    and not ( 'script' ilike any($2) and t.tgisinternal )
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_triggers(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 with tg as (
  select ddlx_create_trigger(oid,$2) as sql 
 from ddlx_get_triggers($1) where is_constraint is null
 order by trigger_name 
 -- per SQL triggers get called in order created vs name as in PostgreSQL
 )
 select coalesce(string_agg(sql,'')||E'\n','')
   from tg
$function$  strict;

--------------------------------------------------------------- ---------------

-- REPLICA IDENTITY (9.4+). 'd' (default) needs no statement. USING INDEX must come
-- after the index exists, so this is emitted together with the indexes.
#if 9.4
CREATE OR REPLACE FUNCTION ddlx_alter_table_replica_identity(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
 select case c.relreplident
          when 'n' then format(E'ALTER TABLE %s REPLICA IDENTITY NOTHING;\n', obj.sql_identifier)
          when 'f' then format(E'ALTER TABLE %s REPLICA IDENTITY FULL;\n', obj.sql_identifier)
          when 'i' then
            case when 'noindexes' ilike any($2) then null
            else (select format(E'ALTER TABLE %s REPLICA IDENTITY USING INDEX %I;\n',
                                obj.sql_identifier, i.relname)
                    from pg_index x
                    join pg_class i on i.oid = x.indexrelid
                   where x.indrelid = c.oid and x.indisreplident)
            end
        end
   from pg_class c, ddlx_identify('pg_class'::regclass,$1) obj
  where c.oid = $1
    and c.relkind in ('r','p','m')   -- other kinds report 'n' without meaning it
    and c.relreplident <> 'd'
    and not 'lite' ilike any($2)
$$ strict;
#else
CREATE OR REPLACE FUNCTION ddlx_alter_table_replica_identity(regclass, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$ select null::text $$;
#end

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_indexes(regclass,ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
 with
 ii as (select * from ddlx_get_indexes($1) order by name),
 -- just indexes
 a as (
  select coalesce(string_agg(ddlx_create_index(oid,$2),'') || E'\n' , E'') as ddl_idx
    from ii where constraint_name is null and not 'noindexes' ilike any($2)
 ),
 -- constraints
 c as (
  select coalesce(string_agg(format(E'CLUSTER %s USING %I;\n',
                                    class::text,name),e'\n'),'')
         as ddl_cluster
    from ii
   where ii.class = $1 and ii.is_clustered
     and not (constraint_name is not null and 'noconstraints' ilike any($2))
 )
#if 10
 ,
-- statistics
 b as (
  select coalesce(string_agg(ddlx_create(oid),'' order by oid)||E'\n', '') as ddl_stx
    from pg_statistic_ext where stxrelid = $1
 )
select ddl_idx || 
       case when 'lite' ilike any($2)
            then ''
            else ddl_cluster || ddl_stx
       end 
       || coalesce(ddlx_alter_table_replica_identity($1,$2),'')
  from a,b,c
#else
select ddl_idx ||
       case when 'lite' ilike any($2)
            then ''
            else ddl_cluster
       end 
       || coalesce(ddlx_alter_table_replica_identity($1,$2),'')
  from a,c
#end
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_aggregate(regproc)
 RETURNS text LANGUAGE sql STABLE AS $function$ 
  with obj as (select * from ddlx_identify('pg_proc'::regclass,$1))
select 'CREATE AGGREGATE ' ||
#if 9.4
        case
          -- ordered-set and hypothetical-set aggregates need the ORDER BY form
          when a.aggkind <> 'n'
          then format('%s(%s)', cast(a.aggfnoid::regproc as text),
                                pg_get_function_arguments(a.aggfnoid))
          when p.pronargs = 0
          then format('%s(*)', cast(a.aggfnoid::regproc as text))
          else obj.sql_identifier
        end
#else
        case when p.pronargs = 0
             then format('%s(*)', cast(a.aggfnoid::regproc as text))
             else obj.sql_identifier
        end
#end
        || ' (' || E'\n  ' || 
        array_to_string(array[
          'SFUNC = '  || cast(a.aggtransfn::regproc as text),
          'STYPE = ' || format_type(a.aggtranstype,null),
#if 9.4
          case when a.aggtransspace>0 then 'SSPACE = '||a.aggtransspace end,
#end
          'FINALFUNC = ' || cast(nullif(a.aggfinalfn,0)::regproc as text), 
#if 9.4
          case when a.aggfinalextra then 'FINALFUNC_EXTRA' end,
#if 9.6
          'COMBINEFUNC = ' || cast(nullif(a.aggcombinefn,0)::regproc as text), 
          'SERIALFUNC = ' || cast(nullif(a.aggserialfn,0)::regproc as text), 
          'DESERIALFUNC = ' || cast(nullif(a.aggdeserialfn,0)::regproc as text), 
#end
          'INITCOND = ' || quote_literal(a.agginitval), 
#if 9.5
          'MSFUNC = ' || cast(nullif(a.aggmtransfn,0)::regproc as text), 
          'MINVFUNC = ' || cast(nullif(a.aggminvtransfn,0)::regproc as text), 
#if 9.6
          case when a.aggmtranstype>0 
               then 'MSTYPE = '||format_type(a.aggmtranstype,null) end,
#if 9.4
          case when a.aggmtransspace>0 then 'MSSPACE = '||a.aggmtransspace end,
          'MFINALFUNC = ' || cast(nullif(a.aggmfinalfn,0)::regproc as text),
          case when a.aggmfinalextra then 'MFINALFUNC_EXTRA' end,
          'MINITCOND = ' || quote_literal(a.aggminitval), 
#if 9.6
          'PARALLEL = ' || case p.proparallel
            when 's' then 'SAFE'
            when 'r' then 'RESTRICTED'
            when 'u' then null -- 'UNSAFE', default
            else quote_literal(p.proparallel::text)
          end,
#if 11
          case when a.aggfinalmodify <> case when a.aggkind = 'n' then 'r' else 'w' end
               then 'FINALFUNC_MODIFY = ' || case a.aggfinalmodify
                      when 'r' then 'READ_ONLY'
                      when 's' then 'SHAREABLE'
                      when 'w' then 'READ_WRITE' end
          end,
          case when a.aggmfinalfn <> 0
                and a.aggmfinalmodify <> case when a.aggkind = 'n' then 'r' else 'w' end
               then 'MFINALFUNC_MODIFY = ' || case a.aggmfinalmodify
                      when 'r' then 'READ_ONLY'
                      when 's' then 'SHAREABLE'
                      when 'w' then 'READ_WRITE' end
          end,
#if 9.4
          case a.aggkind
            when 'h' then 'HYPOTHETICAL'
          end,
#end
          case when a.aggsortop>0 
               then 'SORTOP = '||cast(a.aggsortop::regoperator as text) end
          ],E',\n  ')
       || E'\n);\n'
  from pg_aggregate a join obj on (true) join pg_proc p on p.oid = a.aggfnoid
 where a.aggfnoid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_function(regproc, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from ddlx_identify('pg_proc'::regclass,$1))
 select
  case when 'compact' ilike any($2) then '' else ddlx_banner(sql_identifier,obj.sql_kind,namespace,owner) end 
  ||
  case obj.sql_kind
    when 'AGGREGATE' then ddlx_create_aggregate($1)
    else trim(trailing E'\n' from pg_get_functiondef($1)) || E';\n'
   end || E'\n' 
   from obj
$function$  strict;

--------------------------------------------------------------- ---------------

#if 9.5
CREATE OR REPLACE FUNCTION ddlx_grants(regrole, text[] default '{}') 
#else
CREATE OR REPLACE FUNCTION ddlx_grants_to_role(oid, text[] default '{}') 
#end
 RETURNS text LANGUAGE sql STABLE AS $function$
with 
q as (
 select format(E'GRANT %I TO %I%s%s;\n',r1.rolname, r2.rolname,
               ' WITH '||nullif(array_to_string(array[
                 'ADMIN '||case when admin_option then 'OPTION' else null end,
#if 16
                 'INHERIT '||case when inherit_option then null else 'FALSE' end,
                 'SET '||case when set_option then null else 'FALSE' end
#else
                 null, null
#end                 
               ],', '),''),
#if 14
               case when 'grantor' ilike any($2) 
                    then ' GRANTED BY '||quote_ident(nullif(r3.rolname,current_user))
               end
#else
               null
#end
              )
        as ddl1
   from pg_auth_members m
   left join pg_roles r1 on (r1.oid=m.roleid)
   left join pg_roles r2 on (r2.oid=m.member)
   left join pg_roles r3 on (r3.oid=m.grantor)
  where (m.member = $1 or m.roleid = $1)
  order by m.roleid = $1,
           cast(r2.rolname as text), 
           cast(r1.rolname as text)
)
select coalesce(string_agg(ddl1,'')||E'\n','')
  from q
$function$  strict;

--------------------------------------------------------------- ---------------

-- Turns a pg_db_role_setting/pg_roles.rolconfig entry 'name=value' into
-- "name TO value" with the value quoted like pg_dump does: list-valued
-- settings are stored in a form that is already valid SQL, the rest are literals.
CREATE OR REPLACE FUNCTION ddlx_set_config_sql(text)
 RETURNS text LANGUAGE sql IMMUTABLE AS $function$
 select case when strpos($1,'=') = 0 then $1
        else substr($1,1,strpos($1,'=')-1) || ' TO ' ||
             case when lower(substr($1,1,strpos($1,'=')-1)) in 
                  ('search_path','temp_tablespaces','session_preload_libraries',
                   'shared_preload_libraries','local_preload_libraries',
                   'synchronous_standby_names')
                  and substr($1,strpos($1,'=')+1) <> ''
                  then substr($1,strpos($1,'=')+1)
                  else quote_literal(substr($1,strpos($1,'=')+1))
             end
        end
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_alter_role_auth(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 select case when rolpassword is not null and not 'nosecrets' ilike any($2)
       then 'ALTER ROLE '|| quote_ident(rolname)||
                  ' ENCRYPTED PASSWORD '||quote_literal(rolpassword)
  end
   from pg_authid where oid = $1
$function$  strict;

#if 9.5
CREATE OR REPLACE FUNCTION ddlx_create_role(regrole)
#else
CREATE OR REPLACE FUNCTION ddlx_create_role(oid)
#end
 RETURNS text
 LANGUAGE sql STABLE
AS $function$ 
with 
q1 as (
 select format(E'CREATE %s %I;\n',
                case when rolcanlogin then 'USER' else 'GROUP' end,
                rolname) as ddl
   from pg_roles a
   left join pg_shdescription d on d.objoid=a.oid
  where a.oid = $1
 )
select ddl
  from q1; 
$function$  strict;

#if 9.5
CREATE OR REPLACE FUNCTION ddlx_alter_role(regrole, text[] default '{}')
#else
CREATE OR REPLACE FUNCTION ddlx_alter_role(oid, text[] default '{}')
#end
 RETURNS text
 LANGUAGE sql STABLE
AS $function$ 
with 
q1 as (
 select 
        format(E'ALTER ROLE %I WITH\n  %s;\n\n',rolname,
                array_to_string(array[
   case when rolcanlogin then 'LOGIN' else 'NOLOGIN' end,
   case when rolsuper then 'SUPERUSER' else 'NOSUPERUSER' end,
   case when rolinherit then 'INHERIT' else 'NOINHERIT' end,
   case when rolcreatedb then 'CREATEDB' else 'NOCREATEDB' end,
   case when rolcreaterole then 'CREATEROLE' else 'NOCREATEROLE' end, 
#if 9.5
   case when rolbypassrls then 'BYPASSRLS' end,
#end
   case when rolreplication then 'REPLICATION' else 'NOREPLICATION' end
                ],E'\n  ')) ||
       array_to_string(array[
   case 
     when description is not null 
     then 'COMMENT ON ROLE '||quote_ident(rolname)||
          ' IS '||quote_literal(description)||E';\n'
   end,
   case when has_table_privilege('pg_catalog.pg_authid'::regclass, 'select')
        then ddlx_alter_role_auth(a.oid,$2)||E';\n'
   end,
   case when rolvaliduntil is not null 
        then 'ALTER ROLE '|| quote_ident(rolname)||
             ' VALID UNTIL '||quote_nullable(rolvaliduntil)||E';\n'
   end,
   case when rolconnlimit>=0  
        then 'ALTER ROLE '|| quote_ident(rolname)||
             ' CONNECTION LIMIT '||rolconnlimit||E';\n'
   end
                ],'') ||
   E'\n'
   as ddl
   from pg_roles a
   left join pg_shdescription d on d.objoid=a.oid
  where a.oid = $1
 ),
q2 as (
 select string_agg('ALTER ROLE ' || quote_ident(rolname)
                   ||' SET '||ddlx_set_config_sql(pg_roles.rolconfig[i])||E';\n','')
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
$function$  strict
set datestyle = iso;

--------------------------------------------------------------- ---------------

#if 9.3
CREATE OR REPLACE FUNCTION ddlx_create_event_trigger(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from pg_event_trigger where oid = $1)
 select
    'CREATE EVENT TRIGGER ' || quote_ident(obj.evtname) ||
    ' ON ' || obj.evtevent || E'\n' ||
    case 
    when obj.evttags is not null
    then '  WHEN tag IN ' || 
      (select '(' || string_agg(quote_nullable(u),', ') || ')' 
         from unnest(obj.evttags) as u) 
        || E'\n'
    else ''
    end ||
    '  EXECUTE PROCEDURE ' || cast(obj.evtfoid as regprocedure) || E';\n' ||
    case obj.evtenabled
      when 'D' then format(E'ALTER EVENT TRIGGER %I DISABLE;\n', obj.evtname)
      when 'R' then format(E'ALTER EVENT TRIGGER %I ENABLE REPLICA;\n', obj.evtname)
      when 'A' then format(E'ALTER EVENT TRIGGER %I ENABLE ALWAYS;\n', obj.evtname)
      else ''
    end
   from obj;
$function$  strict;
#end

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_foreign_data_wrapper(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from pg_foreign_data_wrapper where oid = $1)
 select
    'CREATE FOREIGN DATA WRAPPER ' || quote_ident(obj.fdwname) || E'\n' ||
    case 
    when nullif(obj.fdwhandler,0) is not null
    then '  HANDLER ' || cast(obj.fdwhandler as regproc)
    else '  NO HANDLER'
    end || E'\n' ||
    case 
    when nullif(obj.fdwvalidator,0) is not null
    then '  VALIDATOR ' || cast(obj.fdwvalidator as regproc)
    else '  NO VALIDATOR'
    end ||
    coalesce(E'\nOPTIONS (\n'||
      (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value), 
              E',\n')
         from pg_options_to_table(obj.fdwoptions)
        where not ('nosecrets' ilike any($2) and option_name ~* 'pass(word|wd)|secret|token'))||E'\n)'
    ,'') || E';\n' 
   from obj;
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_server(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from pg_foreign_server where oid = $1)
 select
    'CREATE SERVER ' ||
     case when 'ine' ilike any($2) then 'IF NOT EXISTS ' else '' end  ||
     quote_ident(obj.srvname) ||
     coalesce(E'\nTYPE ' || quote_literal(obj.srvtype),'') ||
     coalesce(E'\nVERSION ' || quote_literal(obj.srvversion),'') ||
     E' FOREIGN DATA WRAPPER ' || 
      (select quote_ident(fdwname)
         from pg_foreign_data_wrapper
        where oid = obj.srvfdw) ||
     coalesce(E'\nOPTIONS (\n'||
      (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value), 
              E',\n')
         from pg_options_to_table(obj.srvoptions)
        where not ('nosecrets' ilike any($2) and option_name ~* 'pass(word|wd)|secret|token'))||E'\n)'
    ,'') || E';\n' 
   from obj;
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_user_mapping(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from ddlx_identify('pg_user_mapping'::regclass,$1) where sql_kind='USER MAPPING')
 select
    'CREATE USER MAPPING '
    || case when 'ine' ilike any($2) then 'IF NOT EXISTS ' else '' end 
    || obj.sql_identifier ||
    coalesce(E'\nOPTIONS (\n'||
      (select string_agg(
              '    '||quote_ident(option_name)||' '||quote_nullable(option_value), 
              E',\n')
         from pg_options_to_table(um.umoptions)
        where not ('nosecrets' ilike any($2) and option_name ~* 'pass(word|wd)|secret|token')
     )||E'\n)'
    ,'') || E';\n' 
   from obj
   -- the view, unlike pg_user_mapping, can be read by non-superusers
   -- (umoptions is NULL there unless the caller may see the options)
   join pg_user_mappings um ON um.umid = obj.oid;
$function$  strict;

#if 9.5
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_policy(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from ddlx_identify('pg_policy'::regclass,$1)),
 pol1 as (
 SELECT
    pol.oid,
    n.nspname AS schemaname,
    c.relname AS tablename,
    pol.polname AS policyname,
        CASE
            WHEN pol.polroles = '{0}'::oid[] 
            THEN array['PUBLIC']::text[]
            ELSE ARRAY( SELECT quote_ident(r.rolname)
               FROM pg_roles r
              WHERE r.oid = ANY (pol.polroles)
              ORDER BY r.rolname)
        END AS roles,
        CASE pol.polcmd
            WHEN 'r'::"char" THEN 'SELECT'::text
            WHEN 'a'::"char" THEN 'INSERT'::text
            WHEN 'w'::"char" THEN 'UPDATE'::text
            WHEN 'd'::"char" THEN 'DELETE'::text
            WHEN '*'::"char" THEN 'ALL'::text
            ELSE NULL::text
        END AS cmd,
#if 10
        CASE pol.polpermissive 
            WHEN true THEN 'PERMISSIVE'
            ELSE 'RESTRICTIVE'
        END AS permissive,
#if 9.5
    pg_get_expr(pol.polqual, pol.polrelid,true) AS qual,
    pg_get_expr(pol.polwithcheck, pol.polrelid,true) AS with_check
   FROM pg_policy pol
     JOIN pg_class c ON c.oid = pol.polrelid
     LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
)
select format(
           E'CREATE POLICY %s\n  %s;\n',
            obj.sql_identifier,
      array_to_string(array[
#if 10
             'AS '||nullif(p.permissive,'PERMISSIVE'),
#if 9.5
             'FOR '||p.cmd,
             'TO '||array_to_string(p.roles,', '),
             'USING ('||p.qual||')',
             'WITH CHECK ('||p.with_check||')'
             ],E'\n  ')
             )
   from obj join pol1 p using (oid);
$function$  strict;
#end

#if 9.5
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_transform(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from pg_transform where oid = $1)
 select format(
           E'CREATE OR REPLACE TRANSFORM %s (\n  %s\n);\n',
           format('FOR %s LANGUAGE %I',
                  format_type(obj.trftype,null),
                  l.lanname),
           -- either function may be missing (0); the clauses are comma separated
           array_to_string(array[
             case when obj.trffromsql <> 0
                  then 'FROM SQL WITH FUNCTION ' || cast(obj.trffromsql::regprocedure as text) end,
             case when obj.trftosql <> 0
                  then 'TO SQL WITH FUNCTION ' || cast(obj.trftosql::regprocedure as text) end
           ],E',\n  ')
        )
   from obj join pg_language l on (l.oid=obj.trflang);
$function$  strict;
#end

#require 10
#if 10
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_publication(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from pg_publication where oid = $1)
 select array_to_string(array[
        format(E'CREATE PUBLICATION %I %sWITH ( publish=%L%s );',
         obj.pubname,
         case when obj.puballtables then 'FOR ALL TABLES ' end,
         array_to_string(array[
     case when obj.pubinsert then 'insert' end
    ,case when obj.pubupdate then 'update' end
    ,case when obj.pubdelete then 'delete' end
#if 11
    ,case when obj.pubtruncate then 'truncate' end
#if 10
         ],','),
#if 13
               case when obj.pubviaroot then ', publish_via_partition_root' end
#else
               null
#if 10
     ),
           (select string_agg(
              format(E'ALTER PUBLICATION %I ADD TABLE %s%s%s;',
                obj.pubname, prrelid::regclass,
#if 15
                      ' ('||(select string_agg(quote_ident(attname),',')
             from unnest(prattrs) u join pg_attribute a on a.attnum=u and a.attrelid=prrelid
          )||')',
                      ' WHERE ('||pg_get_expr(prqual,prrelid)||')'
#else
                      null, null
#if 10
          ),e'\n')
             from pg_publication_rel where prpubid = $1
           ),
#if 15
           (select string_agg(
              format(E'ALTER PUBLICATION %I ADD TABLES IN SCHEMA %s;',
                obj.pubname, pnnspid::regnamespace),e'\n')
             from pg_publication_namespace where pnpubid = $1
           )
#else
           null
#if 10

  ],e'\n') || e'\n'
   from obj
$function$  strict;

--------------------------------------------------------------- ---------------

-- subconninfo is readable by superusers only, and it contains the password.
-- With 'nosecrets' the password is removed from the connection string.
CREATE OR REPLACE FUNCTION ddlx_subscription_conninfo(oid, text[] default '{}')
 RETURNS text LANGUAGE plpgsql STABLE STRICT AS $$
declare
  r text;
begin
  if not has_column_privilege('pg_catalog.pg_subscription'::regclass, 'subconninfo', 'select') then
    return '<conninfo not available: insufficient privileges>';
  end if;
  select subconninfo into r from pg_catalog.pg_subscription where oid = $1;
  if 'nosecrets' ilike any($2) then
    r := regexp_replace(r, '\s*\mpassword\s*=\s*(''([^''\\]|\\.)*''|\S+)', '', 'gi');
  end if;
  return r;
end
$$;

CREATE OR REPLACE FUNCTION ddlx_create_subscription(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE STRICT AS $$ 
 -- explicit column list: "select *" would need access to subconninfo
 with obj as (select oid, subname, subenabled, subpublications, subslotname, subsynccommit
#if 14
                     , subbinary, substream
#if 15
                     , subtwophasestate, subdisableonerr
#if 16
                     , subpasswordrequired, subrunasowner, suborigin
#if 17
                     , subfailover
#end
                from pg_subscription where oid = $1)
 select format(
           E'CREATE SUBSCRIPTION %I\n  CONNECTION %L\n  PUBLICATION %s\n  WITH ( %s );\n',
     obj.subname,
     ddlx_subscription_conninfo(obj.oid,$2),
     (select string_agg(quote_ident(u.p),', ' order by u.i)
        from unnest(obj.subpublications) with ordinality as u(p,i)),
     array_to_string(array[
    'connect='||(obj.subenabled::text),
    'enabled='||(obj.subenabled::text),
#if 14
    'binary='||(obj.subbinary::text),
    'streaming='||
      case obj.substream::text
      when 'f' then 'off'::text
      when 't' then 'on'::text
      when 'p' then 'parallel'::text
      else obj.substream::text
      end,
#if 15
    'two_phase='||
      -- state is d(isabled), p(ending) or e(nabled)
      case when obj.subtwophasestate in ('p','e') then 'true' else 'false' end,
    'disable_on_error='||
      case obj.subdisableonerr
      when 'f' then 'false'::text
      when 't' then 'true'::text
      else obj.subdisableonerr::text
      end,
#if 16
    'password_required='||
      case obj.subpasswordrequired
      when 'f' then 'false'::text
      when 't' then 'true'::text
      else obj.subpasswordrequired::text
      end,
    'run_as_owner='||
      case obj.subrunasowner
      when 'f' then 'false'::text
      when 't' then 'true'::text
      else obj.subrunasowner::text
      end,
    'origin='||quote_literal(obj.suborigin::text),
#if 17
    'failover='||
      case obj.subfailover
      when 'f' then 'false'::text
      when 't' then 'true'::text
      else obj.subfailover::text
      end,
#if 10
    'slot_name='||quote_literal(obj.subslotname),
    'synchronous_commit='||quote_literal(obj.subsynccommit)
     ],E',\n         ')	   
     )
   from obj
$$;
#end
#required

--------------------------------------------------------------- ---------------
--  Grants
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_grants_columns(regclass, text[] default '{}') 
 RETURNS text LANGUAGE sql STABLE AS $function$
with
obj as (select * from ddlx_identify('pg_class'::regclass,$1)),
e as (
select attrelid::regclass,attname,
       (aclexplode(attacl)).* 
  from pg_attribute 
 where attrelid=$1 and not attisdropped
 order by privilege_type,attname
),
a as (
 select attname,
        coalesce(quote_ident(r1.rolname),'PUBLIC') as grantor,
        coalesce(quote_ident(r2.rolname),'PUBLIC') as grantee,
        privilege_type,
        case 
        when is_grantable then ' WITH GRANT OPTION' else ''
        end as grant_option
   from e
   left join pg_roles r1 on (r1.oid = e.grantor)
   left join pg_roles r2 on (r2.oid = e.grantee)
),
b as (
select format('GRANT %s (%I) ON %s TO %s%s',
              privilege_type,attname,obj.sql_identifier,
              grantee,grant_option)
       as dcl
  from obj,a
 order by grantor,grantee,privilege_type,attname
)
select coalesce(string_agg(dcl,E';\n')||E';\n','')
  from b
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_grants(regproc, text[] default '{}') 
 RETURNS text LANGUAGE sql STABLE AS $function$
 with 
 obj as (
   -- GRANT accepts FUNCTION (also for aggregates and window functions) or PROCEDURE
   select i.sql_identifier, p.proowner,
          case i.sql_kind when 'PROCEDURE' then 'PROCEDURE' else 'FUNCTION' end as acl_kind,
#if 9.2
          -- a NULL acl means the default privileges
          coalesce(p.proacl, acldefault('f', p.proowner)) as acl
#else
          p.proacl as acl
#end
     from pg_proc p, ddlx_identify('pg_proc'::regclass,$1) i
    where p.oid = $1
 ),
 a as (
   select coalesce(quote_ident(r1.rolname),'PUBLIC') as grantor,
          coalesce(quote_ident(r2.rolname),'PUBLIC') as grantee,
          e.privilege_type,
          case when e.is_grantable then ' WITH GRANT OPTION' else '' end as grant_option
     from obj, aclexplode(obj.acl) e
     left join pg_roles r1 on (r1.oid = e.grantor)
     left join pg_roles r2 on (r2.oid = e.grantee)
    where e.grantee <> obj.proowner -- the owner implicitly has all privileges
 ),
 b as (
   select grantor, grantee, privilege_type,
          format(E'GRANT %s ON %s %s TO %s%s%s;\n',
                 a.privilege_type, obj.acl_kind, obj.sql_identifier,
                 a.grantee, a.grant_option,
#if 14
                 case 
                   when 'grantor' ilike any($2) 
                   then ' GRANTED BY '||nullif(a.grantor,quote_ident(current_role))
                 end
#else
                 null
#end
                ) as dcl
     from a, obj
 )
 select format(E'REVOKE ALL ON %s %s FROM PUBLIC;\n', obj.acl_kind, obj.sql_identifier)
        || coalesce((select string_agg(dcl,'' order by grantor,lower(grantee),privilege_type)
                       from b), '')
   from obj
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_grants(regclass, oid, text[]) 
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify($1,$2)),
a as (
 select coalesce(quote_ident(r1.rolname),'PUBLIC') as grantor,
        coalesce(quote_ident(r2.rolname),'PUBLIC') as grantee,
        privilege_type,
        case 
        when is_grantable then ' WITH GRANT OPTION' else ''
        end as grant_option
   from aclexplode((select acl from obj)) e
   left join pg_roles r1 on (r1.oid = e.grantor)
   left join pg_roles r2 on (r2.oid = e.grantee)
),
b as (
select format('GRANT %s ON %s%s TO %s%s%s;',
              privilege_type,
              case obj.sql_kind
                when 'SERVER' then 'FOREIGN SERVER '
                when 'TABLE' then null
                when 'VIEW' then null
                when 'MATERIALIZED VIEW' then null 
                when 'SEQUENCE' then null 
                when 'FOREIGN TABLE' then null 
                else obj.sql_kind || ' '
              end,
              obj.sql_identifier,
              grantee, -- already quoted (or PUBLIC) in a
              grant_option,
#if 14
              case
	              when 'grantor' ilike any($3) 
                then ' GRANTED BY '||nullif(grantor,quote_ident(current_role))
	            end
#else
              null
#end
             )
       as dcl
  from obj,a where grantee<>quote_ident(obj.owner)
 order by grantor,lower(grantee),privilege_type
),
c as (
  select coalesce(string_agg(dcl,E'\n')||E'\n','') as grants
    from b
)
select case obj.classid
       when 'pg_class'::regclass 
       then c.grants || ddlx_grants_columns(obj.oid::regclass,$3)
--       when 'pg_class'::regclass then ddlx_grants(obj.oid::regclass,$3)
       when 'pg_proc'::regclass then ddlx_grants(obj.oid::regproc,$3)
       when 'pg_roles'::regclass
#if 9.5
       then ddlx_grants(obj.oid::regrole,$3)
#else
       then ddlx_grants_to_role(obj.oid,$3)
#end
       else c.grants
       end
  from obj full join c on true
$function$  strict;
COMMENT ON FUNCTION ddlx_grants(regclass, oid, text[]) 
     IS 'Get SQL GRANT statements for an object by catalog and object id (exact)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_grants(oid, text[] default '{}') 
 RETURNS text LANGUAGE sql STABLE AS $w$
  select ddlx_grants(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$w$ strict;
COMMENT ON FUNCTION ddlx_grants(oid, text[]) 
     IS 'Get SQL GRANT statements for any object by object id';

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_language(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$ 
 with obj as (select * from pg_language where oid = $1)
 select format(
           E'CREATE OR REPLACE %sLANGUAGE %I%s;\n',
           case when obj.lanpltrusted then 'TRUSTED ' end,
           obj.lanname,
           E'\n  '||nullif(array_to_string(array[
            'HANDLER ' || nullif(lanplcallfoid,0)::regproc::text,
            'INLINE ' || nullif(laninline,0)::regproc::text,
            'VALIDATOR ' || nullif(lanvalidator,0)::regproc::text
           ],' '),'')
        )
   from obj;
$function$  strict;

--------------------------------------------------------------- ---------------
--  Dependancy handling
--------------------------------------------------------------- ---------------

-- Core implementation: dependants of the object (classid, objid).
-- Every pg_depend join is made on the (classid, objid) pair, because OIDs
-- are only unique within one catalog. Nodes are kept in normalized form:
-- a view is represented by its pg_class entry, not by its _RETURN rule.
create or replace function ddlx_get_dependants(
 in regclass, in oid, in text[],
 out depth int, out classid regclass, out objid oid, out extid oid
)
returns setof record as $$
with recursive
  tree(depth,classid,objid,objsubid,refclassid,refobjid,refobjsubid,deptype,path)
as (
select 1, -- dependants, initial
       n.classid, n.objid,
       d.objsubid, d.refclassid, d.refobjid, d.refobjsubid, d.deptype,
       array[format('%s:%s',$1::oid,$2), n.key]
  from pg_depend d
  left join pg_rewrite r on
       (d.classid = 'pg_rewrite'::regclass::oid
        and r.oid = d.objid and r.ev_type = '1' and r.rulename = '_RETURN')
 cross join lateral (
       select c.classid, c.objid,
              format('%s:%s',c.classid::oid,c.objid) as key
         from (select case when r.oid is not null
                           then 'pg_class'::regclass
                           else d.classid::regclass end as classid,
                      coalesce(r.ev_class,d.objid) as objid) c
       ) n
 where d.refclassid = $1::oid and d.refobjid = $2
   and n.key is distinct from format('%s:%s',$1::oid,$2)
#if 12
 union all
select pt.level, -- partitions
       'pg_class'::regclass, pt.relid::oid, 0,
       'pg_class'::regclass::oid, $2, 0, 'n',
       array[format('%s:%s',$1::oid,$2),
             format('%s:%s','pg_class'::regclass::oid,pt.relid::oid)]
  from pg_partition_tree(case when $1 = 'pg_class'::regclass
                              then $2::regclass end) pt
  join pg_class c on (c.oid = pt.relid)
 where pt.parentrelid is not null and pt.relid::oid is distinct from $2
   and c.relkind not in ('I','i')
   and not ('nopartitions' ilike any($3))
#end
 union all
select t.depth+1, -- dependants, recursive
       n.classid, n.objid,
       d.objsubid, d.refclassid, d.refobjid, d.refobjsubid, d.deptype,
       t.path || n.key
  from tree t
  join pg_depend d on (d.refclassid = t.classid::oid and d.refobjid = t.objid)
  left join pg_rewrite r on
       (d.classid = 'pg_rewrite'::regclass::oid
        and r.oid = d.objid and r.ev_type = '1' and r.rulename = '_RETURN')
 cross join lateral (
       select c.classid, c.objid,
              format('%s:%s',c.classid::oid,c.objid) as key
         from (select case when r.oid is not null
                           then 'pg_class'::regclass
                           else d.classid::regclass end as classid,
                      coalesce(r.ev_class,d.objid) as objid) c
       ) n
 where not (n.key = any(t.path)) -- stop at cycles (includes self-reference)
),
q as (
  select classid, objid, max(depth) as depth
    from tree
   where deptype = 'n'
   group by classid, objid
)
select q.depth, q.classid, q.objid, x.extid
  from q
  -- the container whose extension membership also covers the object
  left join lateral (
       select 'pg_class'::regclass::oid as pcls, t.tgrelid as pobj
         from pg_trigger t
        where q.classid = 'pg_trigger'::regclass and t.oid = q.objid
        union all
       select 'pg_class'::regclass::oid, c.conrelid
         from pg_constraint c
        where q.classid = 'pg_constraint'::regclass and c.oid = q.objid
          and c.conrelid <> 0
        union all
       select 'pg_type'::regclass::oid, c.contypid
         from pg_constraint c
        where q.classid = 'pg_constraint'::regclass and c.oid = q.objid
          and c.contypid <> 0
        union all
       select 'pg_class'::regclass::oid, a.adrelid
         from pg_attrdef a
        where q.classid = 'pg_attrdef'::regclass and a.oid = q.objid
       ) p on true
  left join lateral (
       select d.refobjid as extid
         from pg_depend d
        where d.refclassid = 'pg_extension'::regclass::oid
          and d.deptype = 'e' and d.objsubid = 0
          and ((d.classid = q.classid::oid and d.objid = q.objid)
            or (d.classid = p.pcls and d.objid = p.pobj))
        limit 1
       ) x on true
 order by q.depth, q.objid, q.classid;
$$ language sql stable;

COMMENT ON FUNCTION ddlx_get_dependants(regclass, oid, text[])
     IS 'Get dependants of an object given by catalog (classid) and oid';

-- Compatibility wrapper: object given by oid only
create or replace function ddlx_get_dependants(
 in oid, in text[] default '{}',
 out depth int, out classid regclass, out objid oid, out extid oid
)
returns setof record as $$
select gd.depth, gd.classid, gd.objid, gd.extid
  from (select * from ddlx_identify($1) limit 1) i,
       ddlx_get_dependants(i.classid, i.oid, $2) gd;
$$ language sql stable;

--------------------------------------------------------------- ---------------
--  Search query bodies
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_apropos(
  pattern text default null,
  OUT classid regclass,
  OUT objid oid,
  OUT sql_identifier text,
  OUT sql_kind text,
  OUT language name, 
  OUT owner name,
  OUT comment text, 
  OUT retset boolean,
  OUT namespace name, OUT name name, 
  OUT source text)
 RETURNS SETOF record LANGUAGE sql STABLE AS $function$
with
  rel_kind(k,v) AS (
         VALUES ('r','TABLE'), ('p','TABLE'),('v','VIEW'), 
                ('i','INDEX'), ('I','INDEX'),
                ('S','SEQUENCE'), ('m','MATERIALIZED VIEW'), 
                ('c','TYPE'), ('f','FOREIGN TABLE')
  )
select	'pg_proc'::regclass as classid,
        p.oid AS objid, 
  p.oid::regprocedure::text AS sql_identifier, 
#if 11
         case p.prokind
           when 'f' then 'FUNCTION'
           when 'a' then 'AGGREGATE'
           when 'p' then 'PROCEDURE'
           when 'w' then 'WINDOW FUNCTION'
         end 
#else
         case
           when p.proisagg then 'AGGREGATE'
           else 'FUNCTION' 
         end
#end
        AS sql_kind,
        l.lanname AS language, 
#if 9.5
  p.proowner::regrole::name
#else
  u.rolname
#end
  AS owner,
        obj_description(p.oid) AS comment,
        p.proretset AS retset, 
  s.nspname AS namespace, p.proname AS name,
        p.prosrc AS source
   FROM pg_proc p
   JOIN pg_namespace s ON s.oid = p.pronamespace
   JOIN pg_language l ON l.oid = p.prolang
#unless 9.5
   JOIN pg_roles u ON p.proowner = u.oid
#end
  WHERE ($1 is null
         OR p.oid::regprocedure::text ~ $1
         OR p.prosrc ~ $1
         OR obj_description(p.oid) ~ $1)
    AND has_schema_privilege(s.oid, 'usage')
    AND has_function_privilege(p.oid, 'execute')
UNION
 SELECT	'pg_class'::regclass as classid,
        c.oid AS objid, 
  c.oid::regclass::text AS sql_identifier, 
        k.v AS sql_kind,
        'sql' AS language, 
#if 9.5
  c.relowner::regrole::name
#else
  u.rolname
#end
  AS owner,
        obj_description(c.oid) AS comment,
        true AS retset, 
  s.nspname AS namespace, c.relname AS name,
        pg_get_viewdef(c.oid,true) AS source
   FROM pg_class c JOIN rel_kind k on k.k=c.relkind
   JOIN pg_namespace s ON s.oid = c.relnamespace
#unless 9.5
   JOIN pg_roles u ON c.relowner = u.oid
#end
  WHERE ($1 is null
         OR c.oid::regclass::text ~ $1
         OR pg_get_viewdef(c.oid,true) ~ $1
         OR obj_description(c.oid) ~ $1)
    AND
#if 9.5
        s.oid<>'pg_toast'::regnamespace
#else
        s.nspname<>'pg_toast'
#end
    AND has_schema_privilege(s.oid, 'usage')
    AND has_table_privilege(c.oid, 'select')
ORDER BY 2
$function$;
COMMENT ON FUNCTION ddlx_apropos(text)
     IS 'Search definitions (functions and views) for a regular expression';

--------------------------------------------------------------- ---------------

#if 9.5
CREATE OR REPLACE FUNCTION ddlx_alter_table_rls(regclass)
 RETURNS text LANGUAGE sql STABLE AS $function$
  select case when c.relrowsecurity
         then 'ALTER TABLE '||cast($1 as text)||E' ENABLE ROW LEVEL SECURITY;\n'
         else '' end ||
         case when c.relforcerowsecurity
         then 'ALTER TABLE '||cast($1 as text)||E' FORCE ROW LEVEL SECURITY;\n'
         else '' end
    from pg_class c 
   where oid = $1
$function$  strict;
#end

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_operator(regoper)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_operator'::regclass,$1))
select format(
         E'CREATE OPERATOR %s%s (\n%s%s%s%s%s%s%s%s%s\n);\n\n',
   nullif(obj.namespace,current_schema())||'.',
   obj.name,
         E'  PROCEDURE = '  || cast(o.oprcode::regproc as text),
         case when o.oprleft <> 0 
              then E',\n  LEFTARG = ' || format_type(o.oprleft,null) end,
         case when o.oprright <> 0 
              then E',\n  RIGHTARG = ' || format_type(o.oprright,null) end,
         case when o.oprcom <> 0 
              then E',\n  COMMUTATOR = OPERATOR('||cast(o.oprcom::regoper as text)||')' end,
         case when o.oprnegate <> 0 
              then E',\n  NEGATOR = OPERATOR('||cast(o.oprnegate::regoper as text)||')' end,
         case when o.oprrest <> 0 
              then E',\n  RESTRICT = ' || cast(o.oprrest::regproc as text) end,
         case when o.oprjoin <> 0 
              then E',\n  JOIN = ' || cast(o.oprjoin::regproc as text) end,
         case when o.oprcanhash 
              then E',\n  HASHES' end,
         case when o.oprcanmerge 
              then E',\n  MERGES' end
        )
  from pg_operator o,obj
 where o.oid = $1
$function$  strict;

CREATE OR REPLACE FUNCTION ddlx_create_operator(regoperator)
 RETURNS text LANGUAGE sql STABLE AS $function$
   select ddlx_create_operator($1::regoper)
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_text_search_config(regconfig)
 RETURNS text LANGUAGE sql STABLE AS $function$
with cfg as (select * from pg_ts_config where oid = $1),
     prs as (select * from ddlx_identify('pg_ts_parser'::regclass,
              (select p.oid 
                 from pg_ts_parser p
                 join cfg on p.oid = cfg.cfgparser
             ))),
     -- token names come from the configuration's own parser;
     -- all dictionaries of a token form one chain in a single mapping
     map as (select string_agg(format(
               'ALTER TEXT SEARCH CONFIGURATION %s ADD MAPPING FOR %s WITH %s;',
               cast($1::regconfig as text), quote_ident(tt.alias), m.dicts),e'\n'
                    order by tt.tokid) || e'\n' as ddl
               from (select m.maptokentype,
                            string_agg(cast(m.mapdict::regdictionary as text), ', '
                                       order by m.mapseqno) as dicts
                       from pg_ts_config_map m
                      where m.mapcfg = $1
                      group by m.maptokentype) m
               join (select tokid, alias
                       from ts_token_type((select cfgparser from cfg))) tt
                 on (tt.tokid = m.maptokentype)
            )
select format(E'CREATE TEXT SEARCH CONFIGURATION %s ( PARSER = %s );\n%s',
              cast($1 as text),prs.sql_identifier,
              map.ddl)
  from prs,map;
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_text_search_dict(regdictionary)
 RETURNS text LANGUAGE sql STABLE AS $function$
with dict as (select * from pg_ts_dict where oid = $1),
     tmpl as (select * from ddlx_identify('pg_ts_template'::regclass,
              (select t.oid 
                 from pg_ts_template t
                 join dict on t.oid = dict.dicttemplate
             )))
select format(E'CREATE TEXT SEARCH DICTIONARY %s\n  ( TEMPLATE = %s%s );\n',
       cast($1 as text),
       tmpl.sql_identifier,
       ', '||dict.dictinitoption)
  from dict,tmpl;
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_text_search_parser(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_ts_parser'::regclass,$1))
select format(E'CREATE TEXT SEARCH PARSER %s (\n  %s\n);\n',obj.sql_identifier,
         array_to_string(array[
           'START = '    || cast(nullif(p.prsstart,0)::regproc as text), 
           'GETTOKEN = ' || cast(nullif(p.prstoken,0)::regproc as text), 
           'END = '      || cast(nullif(p.prsend,0)::regproc as text), 
           'LEXTYPES = ' || cast(nullif(p.prslextype,0)::regproc as text), 
           'HEADLINE = ' || cast(nullif(p.prsheadline,0)::regproc as text)
           ],E',\n  ')
        )
  from pg_ts_parser as p, obj
 where p.oid = $1 and obj.classid = 'pg_ts_parser'::regclass
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_text_search_template(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_ts_template'::regclass,$1))
select format(E'CREATE TEXT SEARCH TEMPLATE %s (\n  %s\n);\n',
         obj.sql_identifier,
         array_to_string(array[
           'INIT = '   || cast(nullif(t.tmplinit,0)::regproc as text), 
           'LEXIZE = ' || cast(nullif(t.tmpllexize,0)::regproc as text) 
           ],E',\n  ')
        )
  from pg_ts_template as t, obj
 where t.oid = $1 and obj.classid = 'pg_ts_template'::regclass
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_cast(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_cast'::regclass,$1))
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
  from pg_cast as c, obj
 where c.oid = $1 and obj.classid = 'pg_cast'::regclass
$function$  strict;

--------------------------------------------------------------- ---------------

#if 9.2
-- ALTER DEFAULT PRIVILEGES. An entry without a schema replaces the built-in default
-- ACL, so the owner and PUBLIC are revoked first and everything that remains is
-- granted again; an entry with a schema only adds to the defaults.
CREATE OR REPLACE FUNCTION ddlx_create_default_acl(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
 with obj as (select * from ddlx_identify('pg_default_acl'::regclass,$1) where sql_kind = 'DEFAULT PRIVILEGES'),
 d as (
  select da.*, obj.owner, obj.name as objs,
         format('ALTER DEFAULT PRIVILEGES FOR ROLE %I%s', obj.owner,
                case when da.defaclnamespace <> 0
                     then format(' IN SCHEMA %I', obj.namespace) else '' end) as prefix
    from pg_default_acl da join obj on obj.oid = da.oid
 ),
 g as (
  select d.prefix, d.objs,
         coalesce(quote_ident(r.rolname), 'PUBLIC') as grantee,
         e.is_grantable,
         string_agg(e.privilege_type, ', ' order by e.privilege_type) as privs
    from d, aclexplode(d.defaclacl) e
    left join pg_roles r on r.oid = e.grantee
   group by d.prefix, d.objs, r.rolname, e.grantee, e.is_grantable
 )
 select (select case when d.defaclnamespace = 0
              then format(E'%s REVOKE ALL ON %s FROM PUBLIC;\n%s REVOKE ALL ON %s FROM %I;\n',
                          d.prefix, d.objs, d.prefix, d.objs, d.owner)
              else '' end
           from d)
        || coalesce((select string_agg(
                format(E'%s GRANT %s ON %s TO %s%s;\n', g.prefix, g.privs, g.objs, g.grantee,
                       case when g.is_grantable then ' WITH GRANT OPTION' else '' end),
                '' order by lower(g.grantee), g.is_grantable)
              from g), '')
$function$  strict;

-- Restores the built-in default: no schema entries are left, and a global entry is
-- made equal to acldefault() again (which removes it).
CREATE OR REPLACE FUNCTION ddlx_drop_default_acl(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
 with obj as (select * from ddlx_identify('pg_default_acl'::regclass,$1) where sql_kind = 'DEFAULT PRIVILEGES'),
 d as (
  select da.*, obj.owner, obj.name as objs,
         format('ALTER DEFAULT PRIVILEGES FOR ROLE %I%s', obj.owner,
                case when da.defaclnamespace <> 0
                     then format(' IN SCHEMA %I', obj.namespace) else '' end) as prefix
    from pg_default_acl da join obj on obj.oid = da.oid
 ),
 cur as (   -- everybody who holds something now
  select distinct d.prefix, d.objs, coalesce(quote_ident(r.rolname), 'PUBLIC') as grantee
    from d, aclexplode(d.defaclacl) e left join pg_roles r on r.oid = e.grantee
  union
  select d.prefix, d.objs, 'PUBLIC' from d where d.defaclnamespace = 0
  union
  select d.prefix, d.objs, quote_ident(d.owner) from d where d.defaclnamespace = 0
 ),
 dflt as (  -- what a global entry goes back to
  select d.prefix, d.objs,
         coalesce(quote_ident(r.rolname), 'PUBLIC') as grantee, e.is_grantable,
         string_agg(e.privilege_type, ', ' order by e.privilege_type) as privs
    from d, aclexplode(acldefault(d.defaclobjtype, d.defaclrole)) e
    left join pg_roles r on r.oid = e.grantee
   where d.defaclnamespace = 0
   group by d.prefix, d.objs, r.rolname, e.grantee, e.is_grantable
 )
 select coalesce((select string_agg(format(E'%s REVOKE ALL ON %s FROM %s;\n', prefix, objs, grantee),
                                    '' order by grantee) from cur), '')
        || coalesce((select string_agg(
                format(E'%s GRANT %s ON %s TO %s%s;\n', prefix, privs, objs, grantee,
                       case when is_grantable then ' WITH GRANT OPTION' else '' end),
                '' order by lower(grantee)) from dflt), '')
$function$  strict;
#end

--------------------------------------------------------------- ---------------

#if 10
-- CREATE STATISTICS plus the statistics target (stxstattarget, PG13+; NULL or -1 = default)
CREATE OR REPLACE FUNCTION ddlx_create_statistics(oid)
 RETURNS text LANGUAGE sql STABLE AS $$
 select pg_get_statisticsobjdef(stx.oid) || E';\n'
#if 13
        || case when stx.stxstattarget >= 0
                then format(E'ALTER STATISTICS %s SET STATISTICS %s;\n',
                            obj.sql_identifier, stx.stxstattarget)
                else '' end
#end
   from pg_statistic_ext stx
   join ddlx_identify('pg_statistic_ext'::regclass,stx.oid) obj on obj.classid = 'pg_statistic_ext'::regclass
  where stx.oid = $1
$$ strict;
#end

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_collation(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_collation'::regclass,$1))
select format(E'CREATE COLLATION %s%s (\n  %s\n);\n',
         case when 'ine' ilike any($2) then 'IF NOT EXISTS ' end,
         obj.sql_identifier,
         array_to_string(array[
           -- collcollate/collctype are NULL for ICU and builtin collations (PG15+)
           'LC_COLLATE = '|| quote_literal(collcollate), 
           'LC_CTYPE = '  || quote_literal(collctype)
#if 10
           ,'PROVIDER = ' || 
           case collprovider
           when 'i' then 'icu'
           when 'b' then 'builtin'
--           when 'c' then 'libc'
           when 'd' then 'default'
           end                 
#end
#if 15
           -- colliculocale (PG15,16) became colllocale (PG17); to_jsonb avoids naming either
           ,'LOCALE = ' || quote_literal(coalesce(to_jsonb(c)->>'colllocale',
                                                  to_jsonb(c)->>'colliculocale'))
           ,'RULES = ' || quote_literal(to_jsonb(c)->>'collicurules')
#end
#if 12
           ,'DETERMINISTIC = ' || 
           case when not collisdeterministic then 'false' end
#end
#if 10
           ,'VERSION = ' || quote_literal(collversion)
#end
           ],E',\n  ')
        )
  from pg_collation as c, obj
 where c.oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_conversion(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_conversion'::regclass,$1))
select format(E'CREATE %sCONVERSION %s\n  FOR %L TO %L FROM %s;\n',
        case when c.condefault then 'DEFAULT ' end,
        obj.sql_identifier,
        pg_encoding_to_char(c.conforencoding),
        pg_encoding_to_char(c.contoencoding),
        cast(c.conproc::regproc as text)
       )
  from pg_conversion as c, obj
 where c.oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

#if 9.2
CREATE OR REPLACE FUNCTION ddlx_create_tablespace(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_tablespace'::regclass,$1))
select format(E'CREATE TABLESPACE %s%s;\n',
         obj.sql_identifier,
     ' LOCATION '||quote_literal(pg_tablespace_location(t.oid))
       ) || format(E'%s',
         (
   select string_agg(format('ALTER TABLESPACE %s SET ( %s = %s );', 
          obj.sql_identifier,
          quote_ident(option_name),quote_nullable(option_value)),
          E'\n') as ss
     from pg_options_to_table(t.spcoptions)
         ))
  from pg_tablespace as t, obj
 where t.oid = $1
$function$  strict;
#end

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_database(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_database'::regclass,$1))
select format(E'CREATE DATABASE %s WITH\n  %s;\n\n',
              obj.sql_identifier,
              array_to_string(array[
               -- template1 usually cannot be used with a different encoding or locale
               'TEMPLATE = template0',
               'ENCODING = '||quote_literal(pg_encoding_to_char(d.encoding)),
               'LC_COLLATE = '||quote_literal(d.datcollate),
               'LC_CTYPE = '||quote_literal(d.datctype)
#if 15
               -- daticulocale (PG15,16) became datlocale (PG17); to_jsonb avoids naming either
               ,case d.datlocprovider
                  when 'i' then 'LOCALE_PROVIDER = icu'
                  when 'b' then 'LOCALE_PROVIDER = builtin'
                end
               ,case when d.datlocprovider = 'b'
                     then 'BUILTIN_LOCALE = ' || quote_literal(to_jsonb(d)->>'datlocale')
                     else 'ICU_LOCALE = ' || quote_literal(coalesce(to_jsonb(d)->>'datlocale',
                                                                    to_jsonb(d)->>'daticulocale'))
                end
               ,'ICU_RULES = ' || quote_literal(to_jsonb(d)->>'daticurules')
#end
              ],E'\n  ')
              ) ||
       case when s.oid is not null and s.oid <> 1663 then -- 1663 = pg_default
       format(E'ALTER DATABASE %s SET TABLESPACE %I;\n\n',
              obj.sql_identifier, s.spcname) 
       else '' end 
  from pg_database as d 
  left join pg_tablespace s on (s.oid=d.dattablespace), obj
 where d.oid = $1
$function$  strict;

CREATE OR REPLACE FUNCTION ddlx_alter_database(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_database'::regclass,$1))
select format(E'ALTER DATABASE %s WITH ALLOW_CONNECTIONS %s;\n',
              obj.sql_identifier, d.datallowconn::text) ||
       case when d.datconnlimit>0 then
       format(E'ALTER DATABASE %s WITH CONNECTION LIMIT %s;\n',
              obj.sql_identifier, d.datconnlimit) 
       else '' end ||
       format(E'ALTER DATABASE %s WITH IS_TEMPLATE %s;\n',
              obj.sql_identifier, d.datistemplate::text)
       ||
       (  select coalesce(e'\n'||string_agg(
                   'ALTER DATABASE '||obj.sql_identifier||' SET '||ddlx_set_config_sql(cfg)||';',E'\n'
       ) || E'\n', '')
          from unnest((select setconfig from pg_db_role_setting
                  where setdatabase = $1 and setrole = 0::oid)) as cfg
       )
  from pg_database as d 
  left join pg_tablespace s on (s.oid=d.dattablespace), obj
 where d.oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_access_method(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_am'::regclass,$1))
#if 9.6
select format(E'CREATE ACCESS METHOD %I\n  TYPE %s HANDLER %s;\n\n',
        amname,
        case amtype
          when 'i' then 'INDEX'::text
          else amtype::text
        end,
        cast(amhandler as regproc)
       )
#else
select format(E'-- CREATE ACCESS METHOD %s;\n\n',ddlx_comment_text(quote_ident(amname)))
#end
  from pg_am as am, obj
 where am.oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_operator_class(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_opclass'::regclass,$1))
select format(E'CREATE OPERATOR CLASS %s\n  %sFOR TYPE %s USING %I%s AS %s;\n\n',
        format('%s%I',quote_ident(nullif(obj.namespace,current_schema()))||'.',
                obj.name),
        case when opcdefault then 'DEFAULT ' end,
        format_type(opc.opcintype,null),
        am.amname,
        case when opf.opfname is distinct from opc.opcname
             then format(' FAMILY %I',opf.opfname)
             else '' end,
             coalesce(e'\n  '||(select string_agg(l,e',\n  ') from (
               select format('FUNCTION %s %s',amprocnum,amproc::regprocedure) as l, 1, amprocnum
                 from pg_amproc where amprocfamily = opc.opcfamily 
                union all 
               select format('OPERATOR %s %s %s',amopstrategy,amopopr::regoperator,
                             case amoppurpose
                             when 'o' then 'FOR ORDER BY '||
                                           (select quote_ident(opfname)
                                              from pg_opfamily f
                                             where f.oid = amopsortfamily
                                           )
                             when 's' then 'FOR SEARCH'
                             end
                            ) as l, 0, amopstrategy
                 from pg_amop where amopfamily = opc.opcfamily 
                union all 
               select format('STORAGE %s',opc.opckeytype::regtype),2,0 
                where opc.opckeytype <> 0
                order by 2,3
            ) as item),'STORAGE '||format_type(opc.opcintype,null))
       )
  from pg_opclass as opc join pg_am am on (am.oid=opc.opcmethod)
  left join pg_opfamily opf on (opf.oid=opc.opcfamily), 
       obj
 where opc.oid = obj.oid
$function$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_operator_family(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with obj as (select * from ddlx_identify('pg_opfamily'::regclass,$1))
select format(E'CREATE OPERATOR FAMILY %s;\n',
        obj.sql_identifier,
        amname
       )
  from pg_opfamily as opf join pg_am am on (am.oid=opf.opfmethod), 
       obj
 where opf.oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_amproc(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with 
a as (
 select *
   from pg_amproc as amp
   join pg_opfamily opf on (opf.oid=amp.amprocfamily) 
   join pg_am am on (am.oid=opf.opfmethod)
  where amp.oid = $1),
f as (select * from ddlx_identify('pg_opfamily'::regclass,(select amprocfamily from a)) ),
obj as (select * from ddlx_identify('pg_amproc'::regclass,$1))
select format(E'ALTER OPERATOR FAMILY %s ADD %s %s;\n',
        f.sql_identifier, obj.sql_identifier,
  cast(a.amproc::regprocedure as text)
       )
  from a,f,obj
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_drop_amproc(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with 
a as (
 select *
   from pg_amproc as amp
   join pg_opfamily opf on (opf.oid=amp.amprocfamily) 
   join pg_am am on (am.oid=opf.opfmethod)
  where amp.oid = $1),
f as (select * from ddlx_identify('pg_opfamily'::regclass,(select amprocfamily from a)) ),
obj as (select * from ddlx_identify('pg_amproc'::regclass,$1))
select format(E'ALTER OPERATOR FAMILY %s DROP %s;\n',
        f.sql_identifier,
        obj.sql_identifier
       )
  from a,f,obj
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_amop(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with 
a as (
 select *
   from pg_amop as amp
   join pg_opfamily opf on opf.oid=amp.amopfamily
   join pg_am am on am.oid=opf.opfmethod
  where amp.oid = $1),
f as (select * from ddlx_identify('pg_opfamily'::regclass,(select amopfamily from a)) ),
obj as (select * from ddlx_identify('pg_amop'::regclass,$1))
select format(E'ALTER OPERATOR FAMILY %s ADD OPERATOR %s %s (%s) %s;\n',
        f.sql_identifier,
  amopstrategy,
  amopopr::regoper::text,
  array_to_string(array[amoplefttype,amoprighttype]::regtype[],','),
  case amoppurpose
  when 'o' then 'FOR ORDER BY '||
               (select quote_ident(opfname)
             from pg_opfamily f
       where f.oid = a.amopsortfamily)
  when 's' then 'FOR SEARCH'
  end
       )
  from a,f,obj
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_drop_amop(oid)
 RETURNS text LANGUAGE sql STABLE AS $function$
with 
a as (
 select *
   from pg_amop as amp
   join pg_opfamily opf on (opf.oid=amp.amopfamily) 
   join pg_am am on (am.oid=opf.opfmethod)
  where amp.oid = $1),
f as (select * from ddlx_identify('pg_opfamily'::regclass,(select amopfamily from a)) ),
obj as (select * from ddlx_identify('pg_amop'::regclass,$1))
select format(E'ALTER OPERATOR FAMILY %s DROP %s;\n',
        f.sql_identifier,
        obj.sql_identifier
       )
  from a,f,obj
$function$  strict;

--------------------------------------------------------------- ---------------

#if 9.5
CREATE OR REPLACE FUNCTION ddlx_create_schema(regnamespace, text[] default '{}')
#else
CREATE OR REPLACE FUNCTION ddlx_create_schema(oid, text[] default '{}')
#end
 RETURNS text LANGUAGE sql STABLE AS $function$
select format(E'CREATE SCHEMA %s%I;\n',
              case when 'ine' ilike any($2) then 'IF NOT EXISTS ' end,
              n.nspname)
  from pg_namespace n
 where oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_extension(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
select format(E'CREATE EXTENSION %s%I%s VERSION %s;\n',
              case when 'ine' ilike any($2) then 'IF NOT EXISTS ' end,
              e.extname,
              ' SCHEMA '||quote_ident(nullif(n.nspname,current_schema())),
              quote_nullable(e.extversion))
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
 where e.oid = $1
$function$  strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create_type(regtype, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $function$
   select ddlx_create_class(c.oid::regclass,$2) -- type
     from pg_type t
     join pg_class c on (c.oid=t.typrelid)
    where t.oid = $1 and t.typtype = 'c' and c.relkind = 'c'
    union
   select ddlx_create(c.oid::regclass, $2) -- table, etc
     from pg_type t
     join pg_class c on (c.oid=t.typrelid)
    where t.oid = $1 and t.typtype = 'c' and c.relkind <> 'c'
    union
   select case t.typtype
          when 'e' then ddlx_create_type_enum(t.oid)
          when 'd' then ddlx_create_type_domain(t.oid)
          when 'b' then ddlx_create_type_base(t.oid,$2)
#if 9.2
          when 'r' then ddlx_create_type_range(t.oid)
#end
          else format(E'-- UNSUPPORTED TYPE: %s\n', t.typtype)
          end 
     from pg_type t
    where t.oid = $1 and t.typtype <> 'c'
$function$  strict;

--------------------------------------------------------------- ---------------
--  Main script generating functions
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_definitions(
   in regclass, in oid, in options text[],
   out oid oid, out classid regclass, out sql_kind text, out sql_identifier text,
   out base_ddl text, out comment text, out owner text, out storage text, 
   out defaults text, out settings text, out constraints text, out indexes text,
   out triggers text, out rules text, out rls text, out grants text,
   out seclabels text
)
 RETURNS record LANGUAGE sql STABLE AS $$
with obj as (select * from ddlx_identify($1,$2))
  select 
    obj.oid, obj.classid, obj.sql_kind, obj.sql_identifier,
    case obj.classid
    when 'pg_class'::regclass          then ddlx_create_class(oid::regclass,$3)
    when 'pg_type'::regclass           then ddlx_create_type(oid::regtype,$3)
    when 'pg_proc'::regclass           then ddlx_create_function(oid::regproc)
    when 'pg_operator'::regclass       then ddlx_create_operator(oid::regoper)
    when 'pg_opfamily'::regclass       then ddlx_create_operator_family(oid)
    when 'pg_rewrite'::regclass        then ddlx_create_rule(oid)
    when 'pg_ts_config'::regclass      then ddlx_create_text_search_config(oid::regconfig)
    when 'pg_ts_dict'::regclass        then ddlx_create_text_search_dict(oid::regdictionary)
    when 'pg_ts_parser'::regclass      then ddlx_create_text_search_parser(oid)
    when 'pg_ts_template'::regclass    then ddlx_create_text_search_template(oid)
    when 'pg_database'::regclass       then ddlx_create_database(oid)
    when 'pg_constraint'::regclass     then ddlx_create_constraint(oid,$3)
    when 'pg_trigger'::regclass        then ddlx_create_trigger(oid,$3)
    when 'pg_attrdef'::regclass        then ddlx_create_default(oid)
    when 'pg_foreign_data_wrapper'::regclass then ddlx_create_foreign_data_wrapper(oid,$3)
    when 'pg_foreign_server'::regclass then ddlx_create_server(oid,$3)
    when 'pg_user_mapping'::regclass   then ddlx_create_user_mapping(oid,$3)
    when 'pg_cast'::regclass           then ddlx_create_cast(oid)
#if 9.2
    when 'pg_default_acl'::regclass    then ddlx_create_default_acl(oid)
#end
    when 'pg_collation'::regclass      then ddlx_create_collation(oid,$3)
    when 'pg_conversion'::regclass     then ddlx_create_conversion(oid)
    when 'pg_language'::regclass       then ddlx_create_language(oid)
    when 'pg_opclass'::regclass        then ddlx_create_operator_class(oid)
    when 'pg_extension'::regclass      then ddlx_create_extension(oid,$3)
#if 9.5
    when 'pg_roles'::regclass          then ddlx_create_role(oid::regrole)
    when 'pg_namespace'::regclass      then ddlx_create_schema(oid::regnamespace,$3)
#else
    when 'pg_roles'::regclass          then ddlx_create_role(oid)
    when 'pg_namespace'::regclass      then ddlx_create_schema(oid,$3)
#end
#if 9.2
    when 'pg_tablespace'::regclass     then ddlx_create_tablespace(oid)
#if 9.3
    when 'pg_event_trigger'::regclass  then ddlx_create_event_trigger(oid)
    when 'pg_amproc'::regclass         then ddlx_create_amproc(oid)
    when 'pg_amop'::regclass           then ddlx_create_amop(oid)
#if 9.5
    when 'pg_policy'::regclass         then ddlx_create_policy(oid)
    when 'pg_transform'::regclass      then ddlx_create_transform(oid)
#if 9.6
    when 'pg_am'::regclass             then ddlx_create_access_method(oid)
#if 10
    when 'pg_statistic_ext'::regclass  then ddlx_create_statistics(oid)
    when 'pg_publication'::regclass    then ddlx_create_publication(oid)
    when 'pg_subscription'::regclass   then ddlx_create_subscription(oid,$3)
#end
    else
      case
        when obj.sql_kind is not null
        then format(E'-- CREATE UNSUPPORTED OBJECT: %s %s\n',text($2),sql_kind)
        else format(E'-- CREATE UNIDENTIFIED OBJECT: %s\n',text($2))      
      end
    end as base_ddl,
    ddlx_comment(obj.classid,obj.oid,$3) as comment,
    ddlx_alter_owner(obj.classid,obj.oid,$3) as owner,
    ddlx_alter_table_storage(oid) as storage,
    ddlx_alter_table_defaults(oid,$3) as defaults,
    case obj.sql_kind
      when 'ROLE' THEN ddlx_alter_role(oid,$3)
      when 'DATABASE' THEN  ddlx_alter_database(oid)
      when 'SEQUENCE' THEN ddlx_alter_sequence(oid,$3)
      else ddlx_alter_table_settings(oid,$3)
    end as settings,
--    ddlx_alter_table_settings(oid) as settings,
    case when 'lite' ilike any($3) then ''
         else ddlx_create_constraints(oid,$3) end as constraints,
    ddlx_create_indexes(oid,$3) as indexes,
    ddlx_create_triggers(oid,$3) as triggers,
    ddlx_create_rules(oid) as rules,
#if 9.5
     ddlx_alter_table_rls(oid) as rls,
#else
     null::text as rls,
#end
     ddlx_grants(obj.classid,obj.oid,$3) as grants,
#if 9.1
     ddlx_security_label(obj.classid,obj.oid,$3) as seclabels
#else
     null::text as seclabels
#end
    from obj
$$  strict;
comment on function ddlx_definitions(regclass,oid,text[]) 
     is 'Get individial parts of SQL definition for any object by class and object id (exact)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match, 
-- in priority order) and calls the exact version.
CREATE OR REPLACE FUNCTION ddlx_definitions(
   in oid, in options text[] default '{}',
   out oid oid, out classid regclass, out sql_kind text, out sql_identifier text,
   out base_ddl text, out comment text, out owner text, out storage text, 
   out defaults text, out settings text, out constraints text, out indexes text,
   out triggers text, out rules text, out rls text, out grants text,
   out seclabels text
)
 RETURNS record LANGUAGE sql STABLE AS $$
  select d.*
    from (select * from ddlx_identify($1) limit 1) i,
         lateral ddlx_definitions(i.classid, i.oid, $2) d
$$ strict;
comment on function ddlx_definitions(oid,text[]) 
     is 'Get individial parts of SQL definition for any object by object id';

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_alter(regclass, oid, text[])
 RETURNS text LANGUAGE sql STABLE AS $$
with 
obj as (select * from ddlx_identify($1,$2)),
parts as (select * from ddlx_definitions($1,$2,$3))
  select array_to_string( array[
           case when 'lite' ilike any($3) or 'nostorage' ilike any($3) 
                then null else storage end,
           case when 'nodcl' ilike any($3) 
                  or 'noowner' ilike any($3) 
                  or 'lite' ilike any($3) 
                then null
                else case when obj.sql_kind='TABLE' then parts.owner end || e'\n' end,
           defaults,
           case when 'lite' ilike any($3) or 'nosettings' ilike any($3) 
                then null else settings end,
           case when 'lite' ilike any($3) or 'noconstraints' ilike any($3) 
                then null else constraints end,
           case when 'noindexes' ilike any($3) 
                then null else indexes end,
           case when 'lite' ilike any($3) or 'notriggers' ilike any($3) 
                then null else triggers end,
           case when 'lite' ilike any($3) 
                then null else rules end,
           case when 'lite' ilike any($3) or 'nodcl' ilike any($3) 
                then null else rls end
         ],'')
    from obj,parts
$$  strict;
COMMENT ON FUNCTION ddlx_alter(regclass, oid, text[]) 
     IS 'Get SQL ALTER statement for any object by catalog and object id (exact, post-data)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_alter(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $w$
  select ddlx_alter(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$w$ strict;

COMMENT ON FUNCTION ddlx_alter(oid, text[]) 
     IS 'Get SQL ALTER statement for any object by object id (post-data)';
     
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_createonly(regclass, oid, text[])
 RETURNS text LANGUAGE sql STABLE AS $$
with 
obj as (select * from ddlx_identify($1,$2)),
parts as (select * from ddlx_definitions($1,$2,$3))
select array_to_string(array[
        base_ddl,           
  case when 'nocomments' ilike any($3) then null else 
          case when obj.sql_kind is distinct from 'DEFAULT' 
               then parts.comment end
  end || e'\n',
        case when 'nodcl' ilike any($3) 
               or 'noowner' ilike any($3)
               or 'lite' ilike any($3) 
        then null
        else case 
          when 'owner' ilike any($3) 
            or obj.owner is distinct from current_role
          then parts.owner end
        end,
        case when 'lite' ilike any($3) or 'nostorage' ilike any($3) 
             then null else storage end,
        defaults,
        case when 'lite' ilike any($3) or 'nosettings' ilike any($3) 
             then null else settings end,
        seclabels
      ],'')
  from obj,parts
$$ strict;
COMMENT ON FUNCTION ddlx_createonly(regclass, oid, text[]) 
     IS 'Get SQL CREATE statement for any object by catalog and object id (exact, pre-data)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_createonly(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $w$
  select ddlx_createonly(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$w$ strict;

COMMENT ON FUNCTION ddlx_createonly(oid, text[]) 
     IS 'Get SQL CREATE statement for any object by object id (pre-data)';

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_create(regclass, oid, text[])
 RETURNS text LANGUAGE sql STABLE AS $$
with 
obj as (select * from ddlx_identify($1,$2)),
parts as (select * from ddlx_definitions($1,$2,$3))
select array_to_string(array[
        base_ddl,
  case when 'nocomments' ilike any($3) then null else 
          case when obj.sql_kind is distinct from 'DEFAULT' 
          then parts.comment end
  end || e'\n',
        case when 'noalter' ilike any($3) then null
        else array_to_string(array[
          case when 'nodcl' ilike any($3) 
                 or 'noowner' ilike any($3) 
                 or 'lite' ilike any($3) 
               then null
               else case when 'owner' ilike any($3) 
                           or obj.owner is distinct from current_role 
                    then parts.owner end
          end,
          case when 'lite' ilike any($3) or 'nostorage' ilike any($3) 
               then null else storage end,
          defaults,
          case when obj.sql_kind='TABLE' and 'data' ilike any($3)  
               then E'\n' || ddlx_data_restore(obj.oid) || E'\n' end,
          case when 'lite' ilike any($3) or 'nosettings' ilike any($3) 
               then null else settings end,
          case when 'noconstraints' ilike any($3) 
               then null else constraints end, 
           case when 'noindexes' ilike any($3) 
                then null else indexes end,
           case when 'lite' ilike any($3) or 'notriggers' ilike any($3) 
                then null else triggers end,
           case when 'lite' ilike any($3) then null else rules end,
           case when 'lite' ilike any($3) or 'nodcl' ilike any($3) 
                then null else rls end
        ],'') end,
        case when 'nodcl' ilike any($3) or 'nogrants' ilike any($3) 
             then null else grants end,
        seclabels
        ],'')
  from obj,parts
$$ strict;
COMMENT ON FUNCTION ddlx_create(regclass, oid, text[]) 
     IS 'Get SQL CREATE statement for any object by catalog and object id (exact)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_create(oid, text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $w$
  select ddlx_create(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$w$ strict;

COMMENT ON FUNCTION ddlx_create(oid, text[]) 
     IS 'Get SQL CREATE statement for any object by object id. Includes constraints, triggers, indexes...';
     
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_drop(regclass, oid, ddlx_options text[]) 
 RETURNS text LANGUAGE sql STABLE AS $$
 with obj as (select * from ddlx_identify($1,$2))
 select 
   case obj.classid
   when 'pg_constraint'::regclass then ddlx_drop_constraint(oid)
   when 'pg_trigger'::regclass    then ddlx_drop_trigger(oid,$3)
   when 'pg_attrdef'::regclass    then ddlx_drop_default(oid)
   when 'pg_amproc'::regclass     then ddlx_drop_amproc(oid)
   when 'pg_amop'::regclass       then ddlx_drop_amop(oid)
#if 9.2
   when 'pg_default_acl'::regclass then ddlx_drop_default_acl(oid)
#end
   else
     case
       when obj.sql_kind = 'SEQUENCE'
       then ddlx_drop_sequence(oid)
       when obj.sql_kind = 'INDEX'
       then ddlx_drop_index(oid)
       when obj.sql_kind is not null
       then format(E'%sDROP %s %s%s;%s\n',
                   case when obj.sql_kind = 'TABLE' and 'data' ilike any($3) 
                   then ddlx_data_backup(obj.oid) end,
                   obj.sql_kind, 
                   case when 'ie' ilike any($3) then 'IF EXISTS ' end,
                   obj.sql_identifier,
                   case when obj.sql_kind = 'TABLE' and (not 'data' ilike any($3))
                        then ' --==>> !!! ATTENTION !!! <<==--' end
                   )
       else format(E'-- DROP UNIDENTIFIED OBJECT: %s\n',text($2))
      end
    end 
    as ddl
   from obj
$$  strict;
COMMENT ON FUNCTION ddlx_drop(regclass,oid,text[]) 
     IS 'Get SQL DROP statement for any object by catalog and object id (exact)';

-- Bare oid version: resolves the oid through ddlx_identify(oid) (first match,
-- in priority order) and calls the exact version above.
CREATE OR REPLACE FUNCTION ddlx_drop(oid,ddlx_options text[] default '{}') 
 RETURNS text LANGUAGE sql STABLE AS $$
  select ddlx_drop(i.classid, i.oid, $2)
    from (select * from ddlx_identify($1) limit 1) i
$$ strict;

COMMENT ON FUNCTION ddlx_drop(oid,text[]) 
     IS 'Get SQL DROP statement for any object by object id';
     
--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_data_backup(
  IN regclass, ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
 with obj as (select * from ddlx_identify('pg_class'::regclass,$1))
 select format(E'CREATE TEMPORARY TABLE %I AS SELECT * FROM %s;\n',
               obj.name||'$'||obj.oid, obj.sql_identifier)
   from obj
$$;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_data_restore(
  IN regclass, ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
 with obj as (select * from ddlx_identify('pg_class'::regclass,$1)),
      cols as (select string_agg(quote_ident(name),',' order by ord) as cols 
                 from ddlx_describe($1) where gen is null)
 select format(E'INSERT INTO %s(%s)%s\n       SELECT %s\n         FROM %I;\n',
               obj.sql_identifier,cols.cols,
#if 10
               e'\n       OVERRIDING SYSTEM VALUE',
#else
               null,
#end
               cols.cols,obj.name||'$'||obj.oid) ||
        format(E'DROP TABLE %I;\n',
               obj.name||'$'||obj.oid)
   from obj,cols
$$;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_script_parts(
 IN oid, ddlx_options text[] default '{}',
 OUT ddl_create text, OUT ddl_drop text,
 OUT ddl_create_deps text, OUT ddl_drop_deps text)
 RETURNS record LANGUAGE sql STABLE AS $$
with 
ddl as (
select row_number() over(order by gd.depth,gd.objid) as n,
       ddlx_drop(gd.classid,gd.objid,$2||'{script}'::text[]),
       ddlx_create(gd.classid,gd.objid,$2||'{script}'::text[]),
       gd.objid
  from ddlx_get_dependants($1,$2) gd
 where case when 'ext' ilike any($2)
            then gd.classid is distinct from 'pg_extension'::regclass
            else gd.extid is null end
   and gd.classid not in ('pg_amproc'::regclass,'pg_amop'::regclass)
 order by depth,objid
)
select ddlx_create($1,$2||'{script}'::text[]) as ddl_create,
       ddlx_drop($1,$2||'{script}'::text[]) as ddl_drop,
       string_agg(ddlx_create,E'' order by n) as ddl_create_deps,
       string_agg(ddlx_drop,'' order by n desc) as ddl_drop_deps
  from ddl 
$$ strict;

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_script(oid, ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
with p as (
  select *, coalesce(ddl_drop_deps||E'\n','') || coalesce(ddl_drop,'') as drops
    from ddlx_script_parts($1,$2)
)
select array_to_string(array[
       case when 'nowrap' ilike any($2) then null else E'BEGIN;\n' end,
       case when 'nodrop' not ilike all($2) then
         case
           when 'drop' ilike any($2) then drops
           -- a block comment cannot be used if the text could close or nest it
           when drops like '%*/%' or drops like '%/*%' then ddlx_comment_out(drops)
           else E'/*\n' || drops || E'*/\n'
         end
       end,
       ddl_create,
       E'-- DEPENDANTS\n\n'||ddl_create_deps,       
       case when 'nowrap' ilike any($2) then null else E'END;\n' end
       ],E'\n')
  from p
$$ strict;

COMMENT ON FUNCTION ddlx_script(oid, text[]) 
     IS 'Get SQL DDL script for any object and dependants by object id';

--------------------------------------------------------------- ---------------

CREATE OR REPLACE FUNCTION ddlx_script(sql_identifier text, ddlx_options text[] default '{}')
 RETURNS text LANGUAGE sql STABLE AS $$
  select case
    when strpos($1,'(')>0 
    then ddlx_script(cast($1 as regprocedure)::oid, $2)
    else ddlx_script((
         select coalesce(c.oid,t.oid)
           from pg_type t 
           left join pg_class c on (c.oid=t.typrelid and t.typtype = 'c' and c.relkind <> 'c') 
          where t.oid = cast($1 as regtype)::oid
         ),$2)
     end
$$  strict;

COMMENT ON FUNCTION ddlx_script(text, text[]) 
     IS 'Get SQL DDL script for any object and dependants by object name';
