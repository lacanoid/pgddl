\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;
------
CREATE TABLE options (
       name text primary key,
       value text not null,
       regtype regtype not null default('text'::regtype)
);
ALTER TABLE options SET ( parallel_workers = 2 );
select ddlx_script('options');
------
CREATE TABLE measurement (
    city_id         int not null,
    logdate         date not null,
    peaktemp        int,
    unitsales       int
) PARTITION BY RANGE (logdate);

CREATE TABLE measurement_y2006m02 PARTITION OF measurement
    FOR VALUES FROM ('2006-02-01') TO ('2006-03-01');

CREATE TABLE measurement_y2006m03 PARTITION OF measurement
    FOR VALUES FROM ('2006-03-01') TO ('2006-04-01');

CREATE INDEX ON measurement_y2006m02 (logdate);
CREATE INDEX ON measurement_y2006m03 (logdate);

select ddlx_script('measurement');
------
CREATE TABLE customers(cust_id bigint NOT NULL,cust_name varchar(32) NOT NULL,cust_address text,
cust_country text) PARTITION BY LIST(cust_country);
CREATE TABLE customer_ind PARTITION OF customers FOR VALUES IN ('ind');
CREATE TABLE customer_jap PARTITION OF customers FOR VALUES IN ('jap');
INSERT INTO customers VALUES (2039,'Puja','Hyderabad','ind');
SELECT tableoid::regclass,* FROM customers;
SELECT * FROM customer_ind;
UPDATE customers SET cust_country ='jap' WHERE cust_id=2039;
SELECT * FROM customer_jap;

select ddlx_script('customers');
select ddlx_script('customer_jap'); 

create table log (
 ts timestamp,
 code int,
 t text,
 a boolean,
 d varchar collate "C",
 j json
)
partition by range (code,date_trunc('month',ts),t collate "C",a,((code%100)/100));
select ddlx_script('log');

-- statistics
CREATE TABLE test_stat (
    a   int primary key,
    b   int
);
CREATE STATISTICS test_stat1 (dependencies) ON a, b FROM test_stat;

\x
select ddlx_create(oid),ddlx_drop(oid) from pg_statistic_ext where stxname='test_stat1';
\x
select ddlx_script('test_stat');
