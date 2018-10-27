\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

create type test_type_e as enum ('foo','bar','baz','qux');
comment on type test_type_e is 'my enum';
select ddlx_script('test_type_e'::regtype);

create domain test_type_d numeric(10,2) check(value is not null) check(value>6) default 7;
comment on type test_type_d is 'my domain';
select ddlx_script('test_type_d'::regtype);

create type test_type_c as (i integer, t text, d test_type_d);
comment on type test_type_c is 'my class type';
comment on column test_type_c.i is 'my class class column i';
select ddlx_script('test_type_c'::regtype);
select ddlx_script('test_type_c'::regclass);

create domain test_collation_d text collate "C" default '***';
select ddlx_script('test_collation_d'::regtype);

create type int_t;

CREATE OR REPLACE FUNCTION int_t4in(cstring)
 RETURNS int_t
 LANGUAGE internal
 IMMUTABLE STRICT
AS $function$int4in$function$;

CREATE OR REPLACE FUNCTION int_t4out(int_t)
 RETURNS cstring
 LANGUAGE internal
 IMMUTABLE STRICT
AS $function$int4out$function$;

CREATE OR REPLACE FUNCTION int_t4send(int_t)
 RETURNS bytea
 LANGUAGE internal
 IMMUTABLE STRICT
AS $function$int4send$function$;

CREATE OR REPLACE FUNCTION int_t4recv(internal)
 RETURNS int_t
 LANGUAGE internal
 IMMUTABLE STRICT
AS $function$int4recv$function$;

CREATE TYPE int_t (
  INPUT = int_t4in,
  OUTPUT = int_t4out,
  SEND = int_t4send,
  RECEIVE = int_t4recv,
  INTERNALLENGTH = 4,
  PASSEDBYVALUE,
  ALIGNMENT = int4,
  STORAGE = plain,
  CATEGORY = 'N',
  DELIMITER = ',',
  COLLATABLE = false
);

COMMENT ON TYPE int_t IS '-2 billion to 2 billion integer, 4-byte storage (test)';
ALTER TYPE int_t OWNER TO postgres;

select ddlx_create('int_t'::regtype);
select ddlx_create('int_t[]'::regtype);

/*
select ddlx_script('daterange'::regtype);

select ddlx_script('=(integer,integer)'::regoperator);
select ddlx_script('=(text,text)'::regoperator);
*/
