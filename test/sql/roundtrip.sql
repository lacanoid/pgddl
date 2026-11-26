-- Round trip tests: create objects of (nearly) every kind, generate DDL, drop the
-- objects, run the generated DDL and check that the result is identical:
--   * a catalog fingerprint (definitions from pg_get_*def, names, no oids) is unchanged
--   * generating the DDL again gives exactly the same text
-- Needs a superuser. Passing checks produce no output (plpgsql ASSERTs).
-- Written for PostgreSQL 14 or newer.

set client_min_messages = error;

-- ACL normalised by effect: a NULL acl is the default one, the owner's own entries are implied
create function pg_temp.rt_acl(acl aclitem[], objtype "char", owner oid) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s/%s/%s/%s', coalesce(pg_get_userbyid(nullif(e.grantee, 0)), 'PUBLIC'),
                                    e.privilege_type, e.is_grantable, pg_get_userbyid(e.grantor)),
                             ',' order by 1), '')
    from aclexplode(coalesce(acl, acldefault(objtype, owner))) e
   where e.grantee <> owner
$f$;
create function pg_temp.rt_line(t text) returns text language sql immutable as
$f$ select regexp_replace(t, E'\\s+', ' ', 'g') $f$;

-- options without the ones some servers add on their own (pg_attver=<number>, different for every column set)
create function pg_temp.rt_opts(o text[]) returns text language sql immutable as
$f$ select (select array_agg(x order by x) from unnest(o) x where x not like 'pg\_attver=%')::text $f$;

-- helper: fingerprint of everything in a schema, independent of oids
create function pg_temp.rt_fp(sch text) returns text language sql stable as $f$
select string_agg(x, E'\n' order by x) from (
  select format('REL %s %s kind=%s persist=%s opts=%s part=%s repl=%s rls=%s/%s am=%s own=%s acl=%s of=%s ispart=%s',
           c.relname, c.relnamespace::regnamespace, c.relkind, c.relpersistence,
           pg_temp.rt_opts(c.reloptions), pg_get_partkeydef(c.oid), c.relreplident,
           c.relrowsecurity, c.relforcerowsecurity, c.relam::regclass,
           pg_get_userbyid(c.relowner), pg_temp.rt_acl(c.relacl, (case c.relkind when 'S' then 's' else 'r' end)::"char", c.relowner), c.reloftype::regtype, c.relispartition) as x
    from pg_class c where c.relnamespace = sch::regnamespace
  union all
  select format('COL %s.%s %s %s notnull=%s def=%s gen=%s ident=%s coll=%s stor=%s stat=%s opts=%s acl=%s',
           c.relname, a.attname, a.attnum, format_type(a.atttypid, a.atttypmod), a.attnotnull,
           pg_get_expr(d.adbin, d.adrelid), a.attgenerated, a.attidentity,
           a.attcollation::regcollation, a.attstorage, a.attstattarget, pg_temp.rt_opts(a.attoptions), pg_temp.rt_acl(a.attacl, 'c', c.relowner))
    from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
   where c.relnamespace = sch::regnamespace and c.relkind in ('r','p','v','m','f','c')
  union all
  select 'CON ' || c.conrelid::regclass || ' ' || c.conname || ' ' || pg_get_constraintdef(c.oid)
         || ' ' || c.condeferrable || c.condeferred || c.convalidated
    from pg_constraint c where c.connamespace = sch::regnamespace
  union all
  select 'IDX ' || pg_get_indexdef(i.indexrelid) || ' cl=' || i.indisclustered || ' repl=' || i.indisreplident
    from pg_index i join pg_class c on c.oid = i.indrelid where c.relnamespace = sch::regnamespace
  union all
  select 'VIEW ' || c.relname || ' ' || pg_temp.rt_line(pg_get_viewdef(c.oid))
    from pg_class c where c.relnamespace = sch::regnamespace and c.relkind in ('v','m')
  union all
  select 'FUNC ' || p.proname || ' ' || pg_temp.rt_line(pg_get_functiondef(p.oid)) || ' acl=' || pg_temp.rt_acl(p.proacl, 'f', p.proowner)
         || ' sec=' || p.prosecdef || ' own=' || pg_get_userbyid(p.proowner)
    from pg_proc p where p.pronamespace = sch::regnamespace and p.prokind <> 'a'
  union all
  select 'AGG ' || p.proname || ' ' || pg_get_function_arguments(p.oid) || ' ' || a.aggtransfn::text
         || ' ' || a.aggfinalfn::text || ' ' || coalesce(a.agginitval,'') || ' ' || a.aggkind::text
    from pg_proc p join pg_aggregate a on a.aggfnoid = p.oid where p.pronamespace = sch::regnamespace
  union all
  select 'TRG ' || pg_temp.rt_line(pg_get_triggerdef(t.oid)) || ' en=' || t.tgenabled::text
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relnamespace = sch::regnamespace and not t.tgisinternal
  union all
  select 'RULE ' || r.rulename || ' ' || pg_temp.rt_line(pg_get_ruledef(r.oid)) || ' en=' || r.ev_enabled::text
    from pg_rewrite r join pg_class c on c.oid = r.ev_class
   where c.relnamespace = sch::regnamespace and r.rulename <> '_RETURN' and r.ev_enabled <> 'D'   -- disabled rules are deliberately left out
  union all
  select 'POL ' || c.relname || ' ' || p.polname || ' ' || p.polcmd::text || ' ' || p.polpermissive
         || ' ' || coalesce(pg_get_expr(p.polqual, p.polrelid),'') || ' / '
         || coalesce(pg_get_expr(p.polwithcheck, p.polrelid),'') || ' ' || p.polroles::regrole[]::text
    from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = sch::regnamespace
  union all
  select 'TYPE ' || t.typname || ' ' || t.typtype::text || ' ' || format_type(t.typbasetype, t.typtypmod)
         || ' notnull=' || t.typnotnull || ' def=' || coalesce(t.typdefault,'') || ' acl=' || pg_temp.rt_acl(t.typacl, 'T', t.typowner)
    from pg_type t where t.typnamespace = sch::regnamespace and t.typtype <> 'c' and t.typelem = 0 or
         (t.typnamespace = sch::regnamespace and t.typtype in ('d','e','r'))
  union all
  select 'ENUM ' || t.typname || ' ' || e.enumlabel || ' ' || e.enumsortorder
    from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typnamespace = sch::regnamespace
  union all
  select 'RANGE ' || t.typname || ' ' || format_type(r.rngsubtype, null) || ' ' || r.rngcollation::regcollation
    from pg_range r join pg_type t on t.oid = r.rngtypid where t.typnamespace = sch::regnamespace
  union all
  select 'OP ' || o.oprname || ' ' || format_type(o.oprleft, null) || ' ' || format_type(o.oprright, null)
         || ' ' || o.oprcode::text || ' com=' || o.oprcom::regoperator || ' neg=' || o.oprnegate::regoperator
         || ' res=' || o.oprrest::text || ' join=' || o.oprjoin::text || ' h=' || o.oprcanhash || ' m=' || o.oprcanmerge
    from pg_operator o where o.oprnamespace = sch::regnamespace
  union all
  select 'OPF ' || f.opfname || ' ' || am.amname
    from pg_opfamily f join pg_am am on am.oid = f.opfmethod where f.opfnamespace = sch::regnamespace
  union all
  select 'OPC ' || c.opcname || ' ' || am.amname || ' ' || format_type(c.opcintype, null) || ' def=' || c.opcdefault
         || ' fam=' || f.opfname
    from pg_opclass c join pg_am am on am.oid = c.opcmethod join pg_opfamily f on f.oid = c.opcfamily
   where c.opcnamespace = sch::regnamespace
  union all
  select 'COLL ' || c.collname || ' ' || c.collprovider::text || ' ' || coalesce(c.collcollate,'') || ' ' || coalesce(c.collctype,'')
         || ' det=' || c.collisdeterministic
    from pg_collation c where c.collnamespace = sch::regnamespace
  union all
  select 'TSD ' || d.dictname || ' ' || t.tmplname || ' ' || coalesce(d.dictinitoption,'')
    from pg_ts_dict d join pg_ts_template t on t.oid = d.dicttemplate where d.dictnamespace = sch::regnamespace
  union all
  select 'TSC ' || c.cfgname || ' ' || p.prsname || ' ' || coalesce((select string_agg(m.maptokentype || ':' || m.mapseqno || ':' || m.mapdict::regdictionary, ',' order by m.maptokentype, m.mapseqno)
                                                                    from pg_ts_config_map m where m.mapcfg = c.oid), '')
    from pg_ts_config c join pg_ts_parser p on p.oid = c.cfgparser where c.cfgnamespace = sch::regnamespace
  union all
  select 'TST ' || t.tmplname || ' ' || t.tmplinit::text || ' ' || t.tmpllexize::text
    from pg_ts_template t where t.tmplnamespace = sch::regnamespace
  union all
  select 'TSP ' || p.prsname || ' ' || p.prsstart::text || ' ' || p.prstoken::text || ' ' || p.prsend::text
         || ' ' || p.prslextype::text || ' ' || coalesce(nullif(p.prsheadline,0)::regproc::text,'')
    from pg_ts_parser p where p.prsnamespace = sch::regnamespace
  union all
  select 'CONV ' || c.conname || ' ' || c.conforencoding || ' ' || c.contoencoding || ' ' || c.conproc::text || ' ' || c.condefault
    from pg_conversion c where c.connamespace = sch::regnamespace
  union all
  select 'STX ' || s.stxname || ' ' || s.stxkind::text || ' ' || s.stxrelid::regclass || ' ' || s.stxkeys::text
    from pg_statistic_ext s where s.stxnamespace = sch::regnamespace
  union all
  select 'DACL ' || pg_get_userbyid(d.defaclrole) || ' ' || d.defaclobjtype::text || ' ' || d.defaclacl::text
    from pg_default_acl d where d.defaclnamespace = sch::regnamespace
  union all
  select 'DESC ' || d.classoid::regclass || ' ' || d.objsubid || ' ' || d.description
    from pg_description d
   where d.classoid in ('pg_class'::regclass,'pg_type'::regclass,'pg_proc'::regclass,'pg_constraint'::regclass,'pg_trigger'::regclass,'pg_namespace'::regclass)
     and exists (select 1 from pg_class c where d.classoid = 'pg_class'::regclass and c.oid = d.objoid and c.relnamespace = sch::regnamespace)
  union all
  select 'DESC TYPE ' || d.description from pg_description d join pg_type t on t.oid = d.objoid and d.classoid = 'pg_type'::regclass
   where t.typnamespace = sch::regnamespace
  union all
  select 'DESC PROC ' || d.description from pg_description d join pg_proc t on t.oid = d.objoid and d.classoid = 'pg_proc'::regclass
   where t.pronamespace = sch::regnamespace
  union all
  select 'DESC CON ' || d.description from pg_description d join pg_constraint t on t.oid = d.objoid and d.classoid = 'pg_constraint'::regclass
   where t.connamespace = sch::regnamespace
  union all
  select 'DESC TRG ' || d.description from pg_description d join pg_trigger t on t.oid = d.objoid and d.classoid = 'pg_trigger'::regclass
   join pg_class c on c.oid = t.tgrelid where c.relnamespace = sch::regnamespace
) q
$f$;

-- helper: round trip of one object.
-- q returns the oid of the object, which is looked up again after re-creation;
-- fpq (optional) returns a text that must be the same before and after.
create function pg_temp.rt_obj(q text, opts text[] default '{}', fpq text default null) returns void language plpgsql as $f$
declare o oid; s1 text; s2 text; d text; f1 text; f2 text;
begin
  execute q into o;
  assert o is not null, 'object not found: ' || q;
  s1 := ddlx_create(o, opts);
  d  := ddlx_drop(o, '{}');
  assert s1 is not null and d is not null and s1 !~ 'UNSUPPORTED|UNIDENTIFIED' and d !~ 'UNIDENTIFIED',
         'no ddl for ' || q || ': ' || coalesce(s1,'null') || ' / ' || coalesce(d,'null');
  if fpq is not null then execute fpq into f1; end if;
  execute d;
  execute q into o;
  assert o is null, 'object not dropped: ' || q || E'\n' || d;
  -- (no exception block here: ALTER DOMAIN ADD CONSTRAINT cannot run in a subtransaction
  -- after other DDL of the same transaction)
  execute s1;
  execute q into o;
  assert o is not null, 'object not recreated: ' || q || E'\n' || s1;
  if fpq is not null then
    execute fpq into f2;
    assert f1 is not distinct from f2, 'definition differs after round trip: ' || q || E'\n< ' || f1 || E'\n> ' || f2;
  end if;
  s2 := ddlx_create(o, opts);
  assert s1 = s2, 'ddl differs after round trip: ' || q || E'\n--- first\n' || s1 || E'\n--- second\n' || s2;
end $f$;

----------------------------------------------------------------------
-- 1. Everything in one schema, recreated from ddlx_script
----------------------------------------------------------------------
begin;
create role rt_role;
create role rt_role2 login;
create schema rt_s authorization rt_role2;
set local search_path = rt_s, public;

create type rt_enum as enum ('a', 'b', 'c');
create type rt_comp as (x int, y text);
create type rt_range as range (subtype = int4);
create domain rt_dom as text constraint rt_dom_nonempty check (value <> '') not null default 'x';
create collation rt_coll (provider = libc, locale = 'C');
create function rt_trg() returns trigger language plpgsql as $$ begin return null; end $$;
create sequence rt_seq increment 2 start 10 minvalue 4 maxvalue 1000 cache 5 cycle;
create sequence rt_seq_owned;

create table rt_t1 (
  id bigint generated always as identity (start 5 increment 3) primary key,
  name text collate rt_coll not null,
  tags text[] not null default '{}',
  n numeric(10,2) constraint rt_n_pos check (n >= 0),
  status rt_enum default 'a',
  cmp rt_comp,
  d rt_dom,
  rng rt_range,
  gen int generated always as (length(name)) stored,
  seq_id int default nextval('rt_seq_owned'),
  constraint rt_t1_name_key unique (name),
  constraint rt_t1_ex exclude using gist (rng with &&)
) with (fillfactor = 70, autovacuum_enabled = false);
alter sequence rt_seq_owned owned by rt_t1.seq_id;
alter table rt_t1 alter column name set statistics 200;
alter table rt_t1 alter column tags set storage external;
alter table rt_t1 alter column n set (n_distinct = 10);
alter table rt_t1 replica identity using index rt_t1_name_key;
alter table rt_t1 owner to rt_role;
comment on table rt_t1 is 'main table';
comment on column rt_t1.name is 'the name';
comment on constraint rt_n_pos on rt_t1 is 'n must be positive';

create table rt_child (
  id int not null,
  parent bigint references rt_t1 (id) on delete cascade on update set null deferrable initially deferred,
  note text,
  constraint rt_child_pk primary key (id),
  constraint rt_child_chk check (note is null or length(note) < 100) not valid
);
alter table rt_child add constraint rt_child_chk2 check (id > 0) not valid;
alter table rt_child add constraint rt_child_fk2 foreign key (parent) references rt_t1 (id) not valid;
create table rt_inh (extra int) inherits (rt_child);
create table rt_typed of rt_comp (x with options not null);
create unlogged table rt_unl (a int, b int);

create table rt_part (id int, ts date not null, v text) partition by range (ts);
create table rt_part_2020 partition of rt_part for values from ('2020-01-01') to ('2021-01-01');
create table rt_part_2021 partition of rt_part for values from ('2021-01-01') to ('2022-01-01') with (fillfactor = 80);
create table rt_part_def partition of rt_part default;
create table rt_plist (k text, v int) partition by list (k);
create table rt_plist_a partition of rt_plist for values in ('a', 'b');
create table rt_phash (k int) partition by hash (k);
create table rt_phash_0 partition of rt_phash for values with (modulus 2, remainder 0);
create table rt_phash_1 partition of rt_phash for values with (modulus 2, remainder 1);

create index rt_i_expr on rt_t1 (lower(name));
create index rt_i_part on rt_t1 (n) where n > 0;
create index rt_i_inc on rt_t1 (name) include (n);
create index rt_i_gin on rt_t1 using gin (tags);
create index rt_i_brin on rt_t1 using brin (n) with (pages_per_range = 16);
create unique index rt_i_u on rt_child (parent desc nulls last, id);
create index rt_i_opts on rt_t1 (name collate "C" text_pattern_ops) with (fillfactor = 50);
create index rt_i_part_ts on rt_part (ts);
alter table rt_t1 cluster on rt_i_expr;
comment on index rt_i_expr is 'lower name';

create view rt_v with (security_barrier = true) as select id, name from rt_t1;
create view rt_v_co as select id, n from rt_t1 where n > 0 with local check option;
create view rt_v_nested as select * from rt_v;
create materialized view rt_mv as select id, n from rt_t1 with no data;
create unique index rt_mv_i on rt_mv (id);
comment on view rt_v is 'a view';
comment on materialized view rt_mv is 'a materialized view';

create function rt_f_sql(a int, b int default 2) returns int language sql immutable strict parallel safe as 'select a + b';
create function rt_f_plpgsql(t text) returns setof text language plpgsql stable security definer
  set search_path = pg_catalog, pg_temp cost 50 rows 20 as $$ begin return next t; end $$;
create function rt_f_out(a int, out b int, out c text) language sql as 'select a, ''x''::text';
create function rt_f_variadic(variadic xs int[]) returns int language sql as 'select array_length(xs, 1)';
create function rt_f_win() returns int language sql leakproof as 'select 1';
create procedure rt_proc(a int, inout b text default 'z') language plpgsql as $$ begin b := b || a; end $$;
create function rt_eq(a rt_comp, b rt_comp) returns boolean language sql immutable as 'select a.x = b.x and a.y is not distinct from b.y';
create function rt_sfunc(int, int) returns int language sql immutable as 'select $1 + $2';
create function rt_ffunc(int) returns int language sql immutable as 'select $1 * 2';
create aggregate rt_agg(int) (sfunc = rt_sfunc, stype = int, finalfunc = rt_ffunc, initcond = '0', parallel = safe);
create aggregate rt_agg_h(int) (sfunc = rt_sfunc, stype = int, msfunc = rt_sfunc, minvfunc = rt_sfunc, mstype = int);
create operator === (leftarg = rt_comp, rightarg = rt_comp, function = rt_eq, commutator = ===, hashes);
create operator family rt_opf using btree;
create operator class rt_opc for type int4 using btree family rt_opf as
  operator 1 <, operator 2 <=, operator 3 =, operator 4 >=, operator 5 >, function 1 btint4cmp(int4, int4);
comment on function rt_f_sql(int, int) is 'adds';
comment on type rt_enum is 'an enum';
comment on domain rt_dom is 'a domain';
comment on aggregate rt_agg(int) is 'an aggregate';
comment on operator === (rt_comp, rt_comp) is 'an operator';

create trigger rt_trg_row before insert or update of name, n on rt_t1
  for each row when (new.n is not null) execute function rt_trg();
create trigger rt_trg_stmt after delete or truncate on rt_t1 for each statement execute function rt_trg();
create trigger rt_trg_trans after insert on rt_child referencing new table as nt for each statement execute function rt_trg();
create constraint trigger rt_ctrg after insert on rt_child deferrable initially deferred for each row execute function rt_trg();
create trigger rt_trg_off before update on rt_child for each row execute function rt_trg();
alter table rt_child disable trigger rt_trg_off;
create trigger rt_trg_always after update on rt_child for each row execute function rt_trg();
alter table rt_child enable always trigger rt_trg_always;
comment on trigger rt_trg_row on rt_t1 is 'a trigger';

create rule rt_rule1 as on update to rt_child where old.note is distinct from new.note
  do also select 1;
create rule rt_rule2 as on delete to rt_inh do instead nothing;
create rule rt_rule_off as on insert to rt_unl do also select 1;
alter table rt_unl disable rule rt_rule_off;

alter table rt_t1 enable row level security;
alter table rt_t1 force row level security;
create policy rt_pol on rt_t1 for select using (id > 0);
create policy rt_pol_w on rt_t1 as restrictive for all to rt_role using (n is not null) with check (n > 0);
create policy rt_pol_i on rt_t1 for insert to public, rt_role2 with check (true);
comment on policy rt_pol on rt_t1 is 'a policy';

create text search dictionary rt_dict (template = simple, stopwords = english);
create text search configuration rt_cfg (copy = simple);
alter text search configuration rt_cfg alter mapping for asciiword with rt_dict, simple;
create text search template rt_tmpl (init = dsimple_init, lexize = dsimple_lexize);
create text search parser rt_prs (start = prsd_start, gettoken = prsd_nexttoken, end = prsd_end,
                                  lextypes = prsd_lextype, headline = prsd_headline);
create conversion rt_conv for 'LATIN1' to 'UTF8' from iso8859_1_to_utf8;
create statistics rt_stx (dependencies, ndistinct) on id, name from rt_t1;
create statistics rt_stx_expr on (lower(name)), n from rt_t1;

grant usage on schema rt_s to rt_role;
grant select, insert on rt_t1 to rt_role with grant option;
grant update (name, n) on rt_t1 to rt_role2;
grant select (id) on rt_v to public;
grant usage on sequence rt_seq to rt_role;
grant usage on type rt_enum to rt_role;
revoke execute on function rt_f_sql(int, int) from public;
grant execute on function rt_f_sql(int, int) to rt_role;
grant execute on procedure rt_proc(int, text) to rt_role2;
alter default privileges for role rt_role2 in schema rt_s grant select on tables to rt_role;
alter default privileges in schema rt_s grant execute on functions to rt_role2;
alter function rt_f_plpgsql(text) owner to rt_role;
alter view rt_v owner to rt_role;
alter type rt_comp owner to rt_role;
alter sequence rt_seq owner to rt_role;

set local search_path = rt_s, public;

-- top level objects of the schema in creation order (children such as indexes,
-- constraints, triggers, rules and policies are part of their table's DDL)
create function pg_temp.rt_list() returns table (n int, classid regclass, oid oid, descr text)
language sql stable as $f$
  select (row_number() over (order by x.oid))::int, x.classid, x.oid, x.descr from (
    select 'pg_type'::regclass classid, t.oid, 'type ' || t.typname descr from pg_type t
     where t.typnamespace = 'rt_s'::regnamespace and t.typtype in ('e', 'r', 'd')
    union all
    select 'pg_type'::regclass, t.oid, 'composite ' || t.typname
      from pg_type t join pg_class c on c.oid = t.typrelid
     where t.typnamespace = 'rt_s'::regnamespace and c.relkind = 'c'
    union all
    select 'pg_collation'::regclass, c.oid, 'collation ' || c.collname from pg_collation c
     where c.collnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_class'::regclass, c.oid, 'relation ' || c.relname from pg_class c
     where c.relnamespace = 'rt_s'::regnamespace and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
       and (c.relkind <> 'S' or not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass
                          and d.objid = c.oid and d.refclassid = 'pg_class'::regclass and d.deptype = 'i'))
    union all
    select 'pg_proc'::regclass, p.oid, 'function ' || p.proname from pg_proc p
     where p.pronamespace = 'rt_s'::regnamespace
       and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass
                          and d.objid = p.oid and d.deptype = 'i')
    union all
    select 'pg_operator'::regclass, o.oid, 'operator ' || o.oprname from pg_operator o
     where o.oprnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_opfamily'::regclass, o.oid, 'opfamily ' || o.opfname from pg_opfamily o
     where o.opfnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_opclass'::regclass, o.oid, 'opclass ' || o.opcname from pg_opclass o
     where o.opcnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_ts_dict'::regclass, o.oid, 'tsdict ' || o.dictname from pg_ts_dict o
     where o.dictnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_ts_config'::regclass, o.oid, 'tsconfig ' || o.cfgname from pg_ts_config o
     where o.cfgnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_ts_template'::regclass, o.oid, 'tstemplate ' || o.tmplname from pg_ts_template o
     where o.tmplnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_ts_parser'::regclass, o.oid, 'tsparser ' || o.prsname from pg_ts_parser o
     where o.prsnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_conversion'::regclass, o.oid, 'conversion ' || o.conname from pg_conversion o
     where o.connamespace = 'rt_s'::regnamespace
    union all
    select 'pg_policy'::regclass, o.oid, 'policy ' || o.polname from pg_policy o
      join pg_class c on c.oid = o.polrelid where c.relnamespace = 'rt_s'::regnamespace
    union all
    select 'pg_default_acl'::regclass, o.oid, 'default acl ' || o.defaclobjtype::text from pg_default_acl o
     where o.defaclnamespace = 'rt_s'::regnamespace
  ) x
$f$;

create temp table rt_before as select * from pg_temp.rt_list();
create temp table rt_ddl as
  select b.n, b.descr, ddlx_create(b.classid, b.oid, '{}') as cr, ddlx_drop(b.classid, b.oid, '{}') as dr
    from rt_before b;
create temp table rt_fp as select pg_temp.rt_fp('rt_s') as fp;

do $$
declare r record; f1 text; f2 text; missing text;
begin
  -- the generated DDL is complete and valid-looking for every object
  for r in select * from rt_ddl loop
    assert r.cr is not null and r.dr is not null, 'no ddl for ' || r.descr;
    assert r.cr !~ 'UNSUPPORTED|UNIDENTIFIED' and r.dr !~ 'UNIDENTIFIED', 'unsupported: ' || r.descr || ' ' || r.cr;
  end loop;
  select string_agg(k, ', ') into missing
    from unnest(array['type rt_enum','composite rt_comp','type rt_range','type rt_dom','collation rt_coll',
      'relation rt_seq','relation rt_t1','relation rt_child','relation rt_inh','relation rt_typed','relation rt_unl',
      'relation rt_part','relation rt_part_2020','relation rt_plist','relation rt_phash_0','relation rt_v',
      'relation rt_v_co','relation rt_v_nested','relation rt_mv','function rt_f_sql','function rt_f_plpgsql',
      'function rt_f_out','function rt_f_variadic','function rt_proc','function rt_eq','function rt_trg',
      'function rt_agg','function rt_agg_h','operator ===','opfamily rt_opf','opclass rt_opc','tsdict rt_dict',
      'tsconfig rt_cfg','tstemplate rt_tmpl','tsparser rt_prs','conversion rt_conv','relation rt_seq_owned',
      'policy rt_pol','policy rt_pol_w','policy rt_pol_i']) k
   where not exists (select 1 from rt_ddl where descr = k);
  assert missing is null, 'objects not listed: ' || missing;

  -- drop everything with the generated DROP statements, newest first
  for r in select * from rt_ddl order by n desc loop
    begin
      execute r.dr;
    exception when undefined_table then
      -- a sequence owned by a column goes away with its table
      if r.descr <> 'relation rt_seq_owned' then raise; end if;
    end;
  end loop;
  assert not exists (select 1 from pg_class where relnamespace = 'rt_s'::regnamespace
                      and relkind in ('r','p','v','m','f','S','i','I')), 'relations left behind';
  assert not exists (select 1 from pg_proc where pronamespace = 'rt_s'::regnamespace), 'functions left behind';
  assert not exists (select 1 from pg_type where typnamespace = 'rt_s'::regnamespace), 'types left behind';

  -- run the generated CREATE statements, oldest first
  for r in select * from rt_ddl order by n loop
    begin
      execute r.cr;
    exception when others then
      raise exception 'create failed for %: % (%)', r.descr, sqlerrm, r.cr;
    end;
  end loop;

  f1 := (select fp from rt_fp);
  f2 := pg_temp.rt_fp('rt_s');
  assert f1 = f2, 'catalog fingerprint differs after recreation: ' ||
    (select string_agg(l, E'\n') from (
       select '< ' || l as l from unnest(string_to_array(f1, E'\n')) l
        where l not in (select unnest(string_to_array(f2, E'\n')))
       union all
       select '> ' || l from unnest(string_to_array(f2, E'\n')) l
        where l not in (select unnest(string_to_array(f1, E'\n')))) d);

  -- and the generated DDL is stable
  for r in select a.descr, a.cr as c1, ddlx_create(l.classid, l.oid, '{}') as c2
             from rt_ddl a join pg_temp.rt_list() l using (n) loop
    assert r.c1 = r.c2, 'ddl of ' || r.descr || E' differs after round trip\n--- first\n' || r.c1 || E'\n--- second\n' || r.c2;
  end loop;
end $$;
rollback;

----------------------------------------------------------------------
-- 2. Objects that live outside schemas, and single constraints, indexes,
--    triggers, rules, policies, statistics and defaults
----------------------------------------------------------------------
begin;
create role rt_grp;
create role rt_g1 login createdb createrole connection limit 3 valid until '2099-01-01 00:00:00+00' noinherit;
alter role rt_g1 set search_path = public, pg_catalog;
alter role rt_g1 set work_mem = '8MB';
grant rt_grp to rt_g1 with admin option;
comment on role rt_g1 is 'a login role';
create schema rt_g;
set local search_path = rt_g, public;
\o /dev/null

-- roles
select pg_temp.rt_obj('select oid from pg_roles where rolname = ''rt_grp''', '{}',
  $q$select rolname || rolsuper || rolinherit || rolcreaterole || rolcreatedb || rolcanlogin || rolreplication
            || rolconnlimit || coalesce(rolvaliduntil::text, '') || coalesce(rolconfig::text, '')
       from pg_roles where rolname = 'rt_grp'$q$);
-- (rt_g1 is the member and the grantor's target: recreate it as well; the role comment is part of it)
select pg_temp.rt_obj('select oid from pg_roles where rolname = ''rt_g1''', '{}',
  $q$select rolname || rolsuper || rolinherit || rolcreaterole || rolcreatedb || rolcanlogin || rolreplication
            || rolconnlimit || coalesce(rolvaliduntil::text, '') || coalesce(rolconfig::text, '')
            || coalesce(shobj_description(oid, 'pg_authid'), '')
       from pg_roles where rolname = 'rt_g1'$q$);

-- foreign data wrapper, server, user mapping, foreign table
create foreign data wrapper rt_fdw;
create server rt_srv type 'pg' version '1.0' foreign data wrapper rt_fdw options (host 'h', port '5432');
create user mapping for rt_g1 server rt_srv options (user 'u', password 'secret');
create user mapping for public server rt_srv;
create foreign table rt_ft (a int options (column_name 'b') not null, c text default 'x')
  server rt_srv options (schema_name 's', table_name 't');
comment on foreign table rt_ft is 'a foreign table';
comment on foreign data wrapper rt_fdw is 'a wrapper';
comment on server rt_srv is 'a server';
grant usage on foreign data wrapper rt_fdw to rt_grp;
grant usage on foreign server rt_srv to rt_grp;
alter server rt_srv owner to rt_g1;
do $$
begin
  assert ddlx_create((select umid from pg_user_mappings where srvname = 'rt_srv' and usename = 'rt_g1'), '{nosecrets}') not like '%secret%',
         'nosecrets leaves the password out';
  assert ddlx_create((select umid from pg_user_mappings where srvname = 'rt_srv' and usename = 'rt_g1')) like '%secret%',
         'password is part of the mapping by default';
end $$;
select pg_temp.rt_obj('select umid from pg_user_mappings where srvname = ''rt_srv'' and usename = ''rt_g1''', '{}',
  $q$select srvname || usename || coalesce(umoptions::text, '') from pg_user_mappings
      where srvname = 'rt_srv' and usename = 'rt_g1'$q$);
select pg_temp.rt_obj('select umid from pg_user_mappings where srvname = ''rt_srv'' and usename = ''public''');
select pg_temp.rt_obj('select to_regclass(''rt_g.rt_ft'')::oid', '{}',
  $q$select (select string_agg(attname || format_type(atttypid, atttypmod) || attnotnull || coalesce(attfdwoptions::text, ''),
                               ',' order by attnum) from pg_attribute where attrelid = 'rt_g.rt_ft'::regclass and attnum > 0)
            || (select srvname || coalesce(ftoptions::text, '') from pg_foreign_table t join pg_foreign_server s on s.oid = t.ftserver
                 where ftrelid = 'rt_g.rt_ft'::regclass)
            || coalesce(obj_description('rt_g.rt_ft'::regclass, 'pg_class'), '')$q$);
create server rt_srv2 type 'pg' version '1.0' foreign data wrapper rt_fdw options (host 'h', port '5432');
comment on server rt_srv2 is 'a server';
grant usage on foreign server rt_srv2 to rt_grp;
alter server rt_srv2 owner to rt_g1;
select pg_temp.rt_obj('select oid from pg_foreign_server where srvname = ''rt_srv2''', '{}',
  $q$select srvname || coalesce(srvtype, '') || coalesce(srvversion, '') || coalesce(srvoptions::text, '') || pg_get_userbyid(srvowner)
            || coalesce(srvacl::text, '') || coalesce(obj_description(oid, 'pg_foreign_server'), '')
       from pg_foreign_server where srvname = 'rt_srv2'$q$);

-- event trigger
create function rt_evt_f() returns event_trigger language plpgsql as $$ begin null; end $$;
create event trigger rt_evt on ddl_command_end when tag in ('CREATE TABLE', 'DROP TABLE') execute function rt_evt_f();
alter event trigger rt_evt disable;
comment on event trigger rt_evt is 'an event trigger';
select pg_temp.rt_obj('select oid from pg_event_trigger where evtname = ''rt_evt''', '{}',
  $q$select evtname || evtevent::text || evtenabled::text || coalesce(evttags::text, '') || pg_get_userbyid(evtowner)
            || evtfoid::regproc || coalesce(obj_description(oid, 'pg_event_trigger'), '')
       from pg_event_trigger where evtname = 'rt_evt'$q$);

-- publication and subscription
create table rt_pubtab (a int primary key, b int);
create publication rt_pub for table rt_pubtab with (publish = 'insert, update');
create publication rt_pub_all for all tables with (publish = 'insert');
comment on publication rt_pub is 'a publication';
select pg_temp.rt_obj('select oid from pg_publication where pubname = ''rt_pub''', '{}',
  $q$select pubname || puballtables || pubinsert || pubupdate || pubdelete || pubtruncate
            || coalesce((select string_agg(prrelid::regclass::text, ',') from pg_publication_rel where prpubid = p.oid), '')
            || coalesce(obj_description(oid, 'pg_publication'), '')
       from pg_publication p where pubname = 'rt_pub'$q$);
select pg_temp.rt_obj('select oid from pg_publication where pubname = ''rt_pub_all''');
create subscription rt_sub connection 'dbname=rt_nonexistent' publication rt_pub
  with (connect = false, slot_name = none, enabled = false, copy_data = false);
select pg_temp.rt_obj('select oid from pg_subscription where subname = ''rt_sub''', '{}',
  $q$select subname || subenabled || subconninfo || coalesce(subslotname, '') || subpublications::text
       from pg_subscription where subname = 'rt_sub'$q$);

-- cast
create type rt_ct as (a int);
create function rt_ct_to_text(rt_ct) returns text language sql immutable as 'select $1.a::text';
create function rt_text_to_ct(text) returns rt_ct language sql immutable as 'select row($1::int)::rt_ct';
create cast (rt_ct as text) with function rt_ct_to_text(rt_ct) as assignment;
create cast (text as rt_ct) with function rt_text_to_ct(text);
create cast (rt_ct as int) with inout as implicit;
select pg_temp.rt_obj('select oid from pg_cast where castsource = ''rt_g.rt_ct''::regtype and casttarget = ''text''::regtype', '{}',
  $q$select castfunc::regproc || castcontext::text from pg_cast where castsource = 'rt_g.rt_ct'::regtype and casttarget = 'text'::regtype$q$);
select pg_temp.rt_obj('select oid from pg_cast where castsource = ''text''::regtype and casttarget = ''rt_g.rt_ct''::regtype', '{}',
  $q$select castfunc::regproc || castcontext::text || castmethod::text from pg_cast where castsource = 'text'::regtype and casttarget = 'rt_g.rt_ct'::regtype$q$);
select pg_temp.rt_obj('select oid from pg_cast where castsource = ''rt_g.rt_ct''::regtype and casttarget = ''int4''::regtype', '{}',
  $q$select castfunc::regproc || castcontext::text || castmethod::text from pg_cast where castsource = 'rt_g.rt_ct'::regtype and casttarget = 'int4'::regtype$q$);

-- access methods and language
create access method rt_am type table handler heap_tableam_handler;
create access method rt_iam type index handler bthandler;
comment on access method rt_am is 'a table access method';
select pg_temp.rt_obj('select oid from pg_am where amname = ''rt_am''', '{}',
  $q$select amname || amtype::text || amhandler::regproc || coalesce(obj_description(oid, 'pg_am'), '') from pg_am where amname = 'rt_am'$q$);
select pg_temp.rt_obj('select oid from pg_am where amname = ''rt_iam''', '{}',
  $q$select amname || amtype::text || amhandler::regproc from pg_am where amname = 'rt_iam'$q$);
create trusted language rt_lang handler plpgsql_call_handler inline plpgsql_inline_handler validator plpgsql_validator;
comment on language rt_lang is 'a language';
select pg_temp.rt_obj('select oid from pg_language where lanname = ''rt_lang''', '{}',
  $q$select lanname || lanpltrusted || lanplcallfoid::regproc || laninline::regproc || lanvalidator::regproc
            || coalesce(lanacl::text, '') || coalesce(obj_description(oid, 'pg_language'), '')
       from pg_language where lanname = 'rt_lang'$q$);

-- operator family members
create operator family rt_opf2 using btree;
alter operator family rt_opf2 using btree add operator 1 < (int4, int4), operator 3 = (int4, int4), function 1 btint4cmp(int4, int4);
select pg_temp.rt_obj('select oid from pg_amop where amopfamily = (select oid from pg_opfamily where opfname = ''rt_opf2'') and amopstrategy = 1', '{}',
  $q$select amopstrategy::text || amopopr::regoperator::text || amoppurpose::text from pg_amop where amopfamily = (select oid from pg_opfamily where opfname = 'rt_opf2') and amopstrategy = 1$q$);
select pg_temp.rt_obj('select oid from pg_amproc where amprocfamily = (select oid from pg_opfamily where opfname = ''rt_opf2'') and amprocnum = 1', '{}',
  $q$select amprocnum::text || amproc::regproc::text from pg_amproc where amprocfamily = (select oid from pg_opfamily where opfname = 'rt_opf2') and amprocnum = 1$q$);

-- default privileges that belong to no schema
alter default privileges for role rt_g1 grant select on tables to rt_grp;
alter default privileges for role rt_g1 revoke execute on functions from public;
alter default privileges for role rt_g1 grant usage on types to rt_grp with grant option;
select pg_temp.rt_obj('select oid from pg_default_acl where defaclrole = ''rt_g1''::regrole and defaclobjtype = ''r''', '{}',
  $q$select defaclacl::text from pg_default_acl where defaclrole = 'rt_g1'::regrole and defaclobjtype = 'r'$q$);
select pg_temp.rt_obj('select oid from pg_default_acl where defaclrole = ''rt_g1''::regrole and defaclobjtype = ''f''', '{}',
  $q$select defaclacl::text from pg_default_acl where defaclrole = 'rt_g1'::regrole and defaclobjtype = 'f'$q$);
select pg_temp.rt_obj('select oid from pg_default_acl where defaclrole = ''rt_g1''::regrole and defaclobjtype = ''T''', '{}',
  $q$select defaclacl::text from pg_default_acl where defaclrole = 'rt_g1'::regrole and defaclobjtype = 'T'$q$);

-- single constraints, index, trigger, rule, policy, statistics and column default of one table
create table rt_tab (
  id int, a int not null, b text, c int default 5, r int4range,
  constraint rt_tab_pk primary key (id),
  constraint rt_tab_uq unique (a, b),
  constraint rt_tab_ck check (a > 0) no inherit,
  constraint rt_tab_fk foreign key (c) references rt_tab (id) match full on delete set default deferrable,
  constraint rt_tab_ex exclude using gist (r with &&) where (a > 0)
);
alter table rt_tab add constraint rt_tab_ck2 check (c < 100) not valid;
alter table rt_tab add constraint rt_tab_fk2 foreign key (a) references rt_pubtab (a) not valid;
comment on constraint rt_tab_pk on rt_tab is 'primary key';
create index rt_tab_i on rt_tab (lower(b)) where b is not null;
create function rt_tab_trg() returns trigger language plpgsql as $$ begin return new; end $$;
create trigger rt_tab_t before insert on rt_tab for each row execute function rt_tab_trg();
create rule rt_tab_r as on delete to rt_tab do instead nothing;
create policy rt_tab_p on rt_tab for update using (a > 0) with check (a < 100);
create statistics rt_tab_s (mcv) on a, b from rt_tab;
create domain rt_dom2 as int constraint rt_dom2_ck check (value > 0);
comment on constraint rt_dom2_ck on domain rt_dom2 is 'domain constraint';
select pg_temp.rt_obj('select oid from pg_constraint where conname = ''rt_tab_uq''', '{}',
  $q$select pg_get_constraintdef(oid) from pg_constraint where conname = 'rt_tab_uq'$q$);
select pg_temp.rt_obj('select oid from pg_constraint where conname = ''rt_tab_ck''', '{}',
  $q$select pg_get_constraintdef(oid) || connoinherit from pg_constraint where conname = 'rt_tab_ck'$q$);
select pg_temp.rt_obj('select oid from pg_constraint where conname = ''rt_tab_ck2''', '{}',
  $q$select pg_get_constraintdef(oid) || convalidated from pg_constraint where conname = 'rt_tab_ck2'$q$);
select pg_temp.rt_obj('select oid from pg_constraint where conname = ''rt_tab_fk''', '{}',
  $q$select pg_get_constraintdef(oid) || condeferrable || condeferred from pg_constraint where conname = 'rt_tab_fk'$q$);
select pg_temp.rt_obj('select oid from pg_constraint where conname = ''rt_tab_fk2''', '{}',
  $q$select pg_get_constraintdef(oid) || convalidated from pg_constraint where conname = 'rt_tab_fk2'$q$);
select pg_temp.rt_obj('select oid from pg_constraint where conname = ''rt_tab_ex''', '{}',
  $q$select pg_get_constraintdef(oid) from pg_constraint where conname = 'rt_tab_ex'$q$);
select pg_temp.rt_obj('select oid from pg_constraint where conname = ''rt_dom2_ck''', '{}',
  $q$select pg_get_constraintdef(oid) || coalesce(obj_description(oid, 'pg_constraint'), '') from pg_constraint where conname = 'rt_dom2_ck'$q$);
select pg_temp.rt_obj('select to_regclass(''rt_g.rt_tab_i'')::oid', '{}',
  $q$select pg_get_indexdef('rt_g.rt_tab_i'::regclass)$q$);
select pg_temp.rt_obj('select oid from pg_trigger where tgname = ''rt_tab_t''', '{}',
  $q$select pg_get_triggerdef(oid) from pg_trigger where tgname = 'rt_tab_t'$q$);
select pg_temp.rt_obj('select oid from pg_rewrite where rulename = ''rt_tab_r''', '{}',
  $q$select pg_get_ruledef(oid) from pg_rewrite where rulename = 'rt_tab_r'$q$);
select pg_temp.rt_obj('select oid from pg_policy where polname = ''rt_tab_p''', '{}',
  $q$select polcmd::text || pg_get_expr(polqual, polrelid) || pg_get_expr(polwithcheck, polrelid) from pg_policy where polname = 'rt_tab_p'$q$);
select pg_temp.rt_obj('select oid from pg_statistic_ext where stxname = ''rt_tab_s''', '{}',
  $q$select stxkind::text || stxkeys::text from pg_statistic_ext where stxname = 'rt_tab_s'$q$);
select pg_temp.rt_obj('select oid from pg_attrdef where adrelid = ''rt_g.rt_tab''::regclass and adnum = 4', '{}',
  $q$select pg_get_expr(adbin, adrelid) from pg_attrdef where adrelid = 'rt_g.rt_tab'::regclass and adnum = 4$q$);

\o
-- global objects that cannot be dropped here still have to be described
do $$
begin
  assert ddlx_create((select oid from pg_database where datname = current_database())) like '%CREATE DATABASE%', 'database';
  assert ddlx_create((select oid from pg_tablespace where spcname = 'pg_default')) like '%CREATE TABLESPACE%', 'tablespace';
  assert ddlx_create((select oid from pg_extension where extname = 'plpgsql')) like '%CREATE EXTENSION%plpgsql%', 'extension';
  assert ddlx_create((select oid from pg_language where lanname = 'plpgsql')) like '%LANGUAGE%plpgsql%', 'language';
  assert ddlx_drop((select oid from pg_extension where extname = 'plpgsql')) like '%DROP EXTENSION%', 'drop extension';
end $$;
rollback;

----------------------------------------------------------------------
-- 3. Options: what each of them leaves in or out
----------------------------------------------------------------------
begin;
create role rt_o1;
create role rt_o2;
create schema rt_o;
set local search_path = rt_o, public;
create function rt_o_trg() returns trigger language plpgsql as $$ begin return new; end $$;
create sequence rt_o_seq start 100;
do $$ begin perform nextval('rt_o_seq'); end $$;
create table rt_oc (
  id int generated by default as identity primary key,
  v text default 'x' not null,
  n int check (n > 0),
  s int default nextval('rt_o_seq'),
  unique (v)
) with (fillfactor = 80);
alter table rt_oc alter column v set storage external;
alter table rt_oc alter column n set statistics 100;
create index rt_oc_i on rt_oc (n);
create trigger rt_oc_t before insert on rt_oc for each row execute function rt_o_trg();
alter table rt_oc enable row level security;
comment on table rt_oc is 'oc table';
comment on column rt_oc.v is 'oc column';
comment on index rt_oc_i is 'oc index';
comment on trigger rt_oc_t on rt_oc is 'oc trigger';
comment on constraint rt_oc_v_key on rt_oc is 'oc constraint';
grant select on rt_oc to rt_o2;
alter table rt_oc owner to rt_o1;
insert into rt_oc (v, n) values ('a', 1), ('b', 2);
do $$
declare t oid := 'rt_o.rt_oc'::regclass::oid; base text; s text;
begin
  base := ddlx_create(t);
  assert base like '%CREATE TABLE rt_oc%' and base like '%COMMENT ON TABLE rt_oc%' and base like '%COMMENT ON COLUMN rt_oc.v%'
     and base like '%COMMENT ON INDEX%rt_oc_i%' and base like '%COMMENT ON TRIGGER rt_oc_t%'
     and base like '%COMMENT ON CONSTRAINT rt_oc_v_key%', 'default output has all comments';
  assert base like '%GRANT SELECT ON rt_oc TO rt_o2%', 'default output has grants';
  assert base like '%OWNER TO rt_o1%', 'default output has the owner';
  assert base like '%CREATE INDEX rt_oc_i%' and base like '%CREATE TRIGGER rt_oc_t%' and base like '%ADD CONSTRAINT%', 'children';
  assert base like '%SET STORAGE external%' and base like '%SET STATISTICS 100%' and base like '%fillfactor%', 'storage and settings';
  assert base like '%ENABLE ROW LEVEL SECURITY%', 'rls';
  assert base like '%ALTER SEQUENCE rt_o_seq OWNED BY%' or base like '%SET DEFAULT nextval%', 'serial default';
  assert base not like '%INSERT INTO%' and base not like '%setval%', 'no data by default';

  s := ddlx_create(t, '{nocomments}');
  assert s not like '%COMMENT ON%' and s like '%CREATE TABLE%' and s like '%GRANT%', 'nocomments';
  s := ddlx_create(t, '{nogrants}');
  assert s not like '%GRANT%' and s like '%COMMENT ON TABLE%' and s like '%OWNER TO%', 'nogrants';
  s := ddlx_create(t, '{noowner}');
  assert s not like '%OWNER TO%' and s like '%GRANT%', 'noowner';
  s := ddlx_create(t, '{nodcl}');
  assert s not like '%GRANT%' and s not like '%OWNER TO%' and s like '%COMMENT ON TABLE%', 'nodcl';
  s := ddlx_create(t, '{noindexes}');
  assert s not like '%CREATE INDEX%' and s like '%CREATE TRIGGER%' and s like '%ADD CONSTRAINT%', 'noindexes';
  s := ddlx_create(t, '{notriggers}');
  assert s not like '%CREATE TRIGGER%' and s like '%CREATE INDEX%', 'notriggers';
  s := ddlx_create(t, '{noconstraints}');
  assert s not like '%ADD CONSTRAINT%' and s like '%CREATE INDEX%', 'noconstraints';
  s := ddlx_create(t, '{nostorage}');
  assert s not like '%SET STORAGE%' and s like '%CREATE TABLE%', 'nostorage';
  s := ddlx_create(t, '{nosettings}');
  assert s not like '%SET STATISTICS%' and s like '%SET STORAGE%' and s like '%fillfactor%', 'nosettings: ' || s;
  s := ddlx_create(t, '{noalter}');
  assert s like '%CREATE TABLE%' and s not like '%CREATE INDEX%' and s not like '%CREATE TRIGGER%'
     and s not like '%ADD CONSTRAINT%' and s not like '%SET STORAGE%', 'noalter';
  s := ddlx_create(t, '{lite}');
  assert s like '%CREATE TABLE%' and s not like '%CREATE TRIGGER%' and s not like '%OWNER TO%'
     and s not like '%SET STORAGE%' and s not like '%SET STATISTICS%' and s not like '%ADD CONSTRAINT%'
     and s like '%CONSTRAINT rt_oc_pkey PRIMARY KEY (id)%' and s like '%DEFAULT ''x''%', 'lite: ' || s;
  s := ddlx_create(t, '{ine}');
  assert s like '%CREATE TABLE IF NOT EXISTS rt_oc%', 'ine';
  s := ddlx_create(t, '{data}');
  assert s like '%INSERT INTO rt_oc%', 'data restores the rows: ' || s;
  s := ddlx_drop(t, '{data}');
  assert s like '%CREATE TEMPORARY TABLE%SELECT * FROM rt_oc%' and s like '%DROP TABLE rt_oc%', 'data backup: ' || s;
  s := ddlx_drop(t, '{ie}');
  assert s like '%DROP TABLE IF EXISTS rt_oc%', 'ie';
  s := ddlx_drop(t);
  assert s like '%DROP TABLE rt_oc%ATTENTION%', 'dropping a table is flagged';

  -- sequences: setval keeps the current position
  s := ddlx_create('rt_o_seq'::regclass::oid, '{setval}');
  assert s like '%CREATE SEQUENCE rt_o_seq%' and s like '%setval%', 'setval option: ' || s;
  s := ddlx_create('rt_o_seq'::regclass::oid);
  assert s not like '%setval%', 'no setval by default';
  s := ddlx_drop('rt_o_seq'::regclass::oid, '{ie}');
  assert s like '%DROP SEQUENCE%', 'drop sequence';

  -- scripts
  s := ddlx_script(t, '{nowrap}');
  assert s like '%CREATE TABLE rt_oc%' and s not like '%BEGIN;%', 'nowrap';
  s := ddlx_script(t);
  assert s like E'BEGIN;%END;%', 'wrapped in a transaction';
  assert ddlx_script(t, '{nodrop,nowrap}') not like '%DROP TABLE%', 'nodrop';
end $$;
rollback;

----------------------------------------------------------------------
-- 4. Comments: only non-null ones by default, NULL ones with 'comments', none with 'nocomments'
----------------------------------------------------------------------
begin;
create schema rt_n;
create role rt_n1;
set local search_path = rt_n, public;
create function rt_n_trg() returns trigger language plpgsql as $$ begin return new; end $$;
create table rt_nc (id int primary key, v text unique, w text);
create index rt_nc_i on rt_nc (w);
create trigger rt_nc_t before insert on rt_nc for each row execute function rt_n_trg();
create view rt_nv as select * from rt_nc;
create sequence rt_ns;
create type rt_ne as enum ('a');
do $$
declare t oid := 'rt_n.rt_nc'::regclass::oid; s text; o oid;
begin
  -- nothing has a comment: no COMMENT statement anywhere
  for o in select unnest(array[t, 'rt_n.rt_nc_i'::regclass::oid, 'rt_n.rt_nv'::regclass::oid, 'rt_n.rt_ns'::regclass::oid,
                               'rt_n.rt_ne'::regtype::oid, 'rt_n.rt_n_trg'::regproc::oid,
                               (select oid from pg_trigger where tgname = 'rt_nc_t'),
                               (select oid from pg_constraint where conname = 'rt_nc_pkey'),
                               (select oid from pg_roles where rolname = 'rt_n1'),
                               'rt_n'::regnamespace::oid]) loop
    assert ddlx_create(o) not like '%COMMENT ON%', 'no comment, no statement: ' || ddlx_create(o);
    assert ddlx_comment(o) = '', 'ddlx_comment is empty without a comment';
    assert ddlx_create(o, '{nocomments}') not like '%COMMENT ON%', 'nocomments';
  end loop;
  assert ddlx_script(t, '{nowrap}') not like '%IS NULL%', 'no NULL comments in a script';

  -- 'comments' outputs the NULL ones too
  s := ddlx_create(t, '{comments}');
  assert s like '%COMMENT ON TABLE rt_nc IS NULL;%' and s like '%COMMENT ON COLUMN rt_nc.w IS NULL;%'
     and s like '%COMMENT ON INDEX rt_nc_i IS NULL;%' and s like '%COMMENT ON TRIGGER rt_nc_t ON rt_nc IS NULL;%'
     and s like '%COMMENT ON CONSTRAINT rt_nc_pkey ON rt_nc IS NULL;%', 'comments: ' || s;
  assert ddlx_comment(t, '{comments}') = E'COMMENT ON TABLE rt_nc IS NULL;\n', 'ddlx_comment with comments';
  assert ddlx_create((select oid from pg_roles where rolname = 'rt_n1'), '{comments}') like '%COMMENT ON ROLE rt_n1 IS NULL;%', 'role';

  -- real comments are output by default, and never with nocomments
  comment on table rt_nc is 'tab';
  comment on column rt_nc.w is 'col';
  comment on index rt_nc_i is 'idx';
  comment on trigger rt_nc_t on rt_nc is 'trg';
  comment on constraint rt_nc_pkey on rt_nc is 'con';
  comment on role rt_n1 is 'rol';
  s := ddlx_create(t);
  assert s like '%COMMENT ON TABLE rt_nc IS ''tab'';%' and s like '%COMMENT ON COLUMN rt_nc.w IS ''col'';%'
     and s like '%COMMENT ON INDEX rt_nc_i IS ''idx'';%' and s like '%COMMENT ON TRIGGER rt_nc_t ON rt_nc IS ''trg'';%'
     and s like '%COMMENT ON CONSTRAINT rt_nc_pkey ON rt_nc IS ''con'';%', 'comments by default: ' || s;
  assert s not like '%IS NULL%', 'but no NULL ones: ' || s;
  assert ddlx_create(t, '{nocomments}') not like '%COMMENT ON%', 'nocomments with comments present';
  assert ddlx_create((select oid from pg_roles where rolname = 'rt_n1')) like '%COMMENT ON ROLE rt_n1 IS ''rol'';%', 'role comment';
  assert ddlx_create((select oid from pg_roles where rolname = 'rt_n1'), '{nocomments}') not like '%COMMENT ON%', 'role nocomments';
end $$;
rollback;
