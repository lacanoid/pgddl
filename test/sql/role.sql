\pset null _null_
\pset format unaligned

begin;

create user pgddl_test_user nologin nosuperuser
encrypted password 'md5db6d137a5ac4e8c22bed58e3e6687aca';

alter user pgddl_test_user valid until '2100-01-01';

comment on role pgddl_test_user
is 'pg_ddl test user...';

alter user pgddl_test_user 
set standard_conforming_strings=true;

create role pgddl_test_user2 login connection limit 100;
create role pgddl_test_user3 valid until 'infinity';

grant pgddl_test_user2 to pgddl_test_user;
grant pgddl_test_user3 to pgddl_test_user with admin option;

select ddlx_create(oid) from pg_roles where rolname='pgddl_test_user';

select ddlx_create(oid) from pg_roles where rolname='pgddl_test_user3';

select ddlx_create(oid) from pg_roles where rolname='pgddl_test_user2';

abort;

