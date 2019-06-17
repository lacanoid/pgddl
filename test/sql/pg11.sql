\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

CREATE TABLE customers(cust_id bigint NOT NULL,cust_name varchar(32) NOT NULL,cust_address text,
cust_country text) PARTITION BY LIST(cust_country);
CREATE TABLE customer_ind PARTITION OF customers FOR VALUES IN ('ind');
CREATE TABLE customer_jap PARTITION OF customers FOR VALUES IN ('jap');
CREATE TABLE customer_def PARTITION OF customers DEFAULT;
INSERT INTO customers VALUES (2039,'Puja','Hyderabad','ind');
SELECT tableoid::regclass,* FROM customers;
SELECT * FROM customer_ind;
UPDATE customers SET cust_country ='jap' WHERE cust_id=2039;
SELECT * FROM customer_jap;

select ddlx_script('customers');
select ddlx_script('customer_jap');
select ddlx_script('customer_def');

-- statistics
CREATE TABLE test_stat (
    a   int primary key,
    b   int
);
CREATE STATISTICS test_stat1 (dependencies) ON a, b FROM test_stat;
select ddlx_create(oid) from pg_statistic_ext where stxname='test_stat1';
select ddlx_script('test_stat');

-- test hash partitioning

create table dept (id  int primary key) partition by hash(id) ;
create table dept_1 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 0);
create table dept_2 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 1);
create table dept_3 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 2);
create table dept_4 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 3);
create table dept_5 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 4);
create table dept_6 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 5);
create table dept_7 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 6);
create table dept_8 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 7);
create table dept_9 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 8);
create table dept_10 partition of dept FOR VALUES WITH (MODULUS 10, REMAINDER 9);

select ddlx_script('dept');
select ddlx_script('dept_7');

-- test procedures

CREATE PROCEDURE procedure1(IN p1 TEXT)
AS $$
BEGIN
    RAISE WARNING 'Procedure Parameter: %', p1 ;
END ;
$$
LANGUAGE plpgsql ;
call procedure1('Hello, world!');
select ddlx_script('procedure1(text)');
