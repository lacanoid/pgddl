\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

create table tab_generated (
       a integer,
       b integer,
       c integer generated always as (a+b) stored
);

select ddlx_script('tab_generated');
