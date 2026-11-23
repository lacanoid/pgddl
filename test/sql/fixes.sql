-- Regression tests for four ddlx fixes. Needs a superuser (creates an FDW).
-- Run with:  psql -v ON_ERROR_STOP=1 -f test_fixes.sql   (after loading ddlx)
-- Everything happens in a transaction that is rolled back.
begin;
create schema fix_test;
set local search_path = fix_test, public;

-- 2. FDW without handler and validator
create foreign data wrapper fix_fdw;

do $$
declare s text;
begin
  s := ddlx_create_foreign_data_wrapper(
         (select oid from pg_foreign_data_wrapper where fdwname = 'fix_fdw'));
  assert s like '%NO HANDLER%',   'expected NO HANDLER: '   || s;
  assert s like '%NO VALIDATOR%', 'expected NO VALIDATOR: ' || s;
  assert s not like '%HANDLER -%' and s not like '%VALIDATOR -%',
         'must not print a zero regproc: ' || s;
end $$;
rollback;

-- 3. foreign tables: SERVER is always emitted, OPTIONS only when present
create server fix_srv foreign data wrapper fix_fdw;
create foreign table fix_ft1 (a int) server fix_srv;
create foreign table fix_ft2 (a int) server fix_srv options (k 'v');

begin;
do $$
declare s1 text; s2 text;
begin
  s1 := ddlx_create_table('fix_ft1'::regclass);
  s2 := ddlx_create_table('fix_ft2'::regclass);
  assert s1 like '%SERVER fix_srv%', 'SERVER missing without options: ' || s1;
  assert s1 not like '%OPTIONS%',    'unexpected OPTIONS: ' || s1;
  assert s2 like '%SERVER fix_srv OPTIONS (%', 'SERVER/OPTIONS wrong: ' || s2;
end $$;

-- 4. lite mode: no DEFAULT for generated columns (PG12+)
do $$
declare s text;
begin
  if current_setting('server_version_num')::int >= 120000 then
    execute 'create table fix_gen (a int, b int generated always as (a * 2) stored, c int default 5)';
    s := ddlx_create_table('fix_gen'::regclass, '{lite}');
    assert s like '%GENERATED ALWAYS AS (%', 'generated clause missing: ' || s;
    assert s like '%DEFAULT 5%',             'lite must keep normal defaults: ' || s;
    assert (length(s) - length(replace(s, ' DEFAULT ', ''))) / length(' DEFAULT ') = 1,
           'exactly one DEFAULT expected (column c): ' || s;
  end if;
end $$;

rollback;

begin;
-- 5. extension rows: real schema name and quoted identifier
do $$ begin
  assert exists (select 1 from pg_extension), 'need at least one extension';
  assert not exists (
    select 1
      from pg_extension e
     cross join lateral ddlx_identify(e.oid) i
     where i.classid = 'pg_extension'::regclass
       and (i.sql_identifier <> quote_ident(e.extname)
            or i.namespace is distinct from
               (select nspname from pg_namespace where oid = e.extnamespace))),
    'extension identity must use quote_ident and the schema name';
end $$;

rollback;
