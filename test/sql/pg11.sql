\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

CREATE TABLE customers(cust_id bigint NOT NULL,cust_name varchar(32) NOT NULL,cust_address text,
cust_country text) PARTITION BY LIST(cust_country);
CREATE TABLE customer_ind PARTITION OF customers FOR VALUES IN ('ind');
CREATE TABLE customer_jap PARTITION OF customers FOR VALUES IN ('jap');
CREATE TABLE customers_def PARTITION OF customers DEFAULT;
INSERT INTO customers VALUES (2039,'Puja','Hyderabad','ind');
SELECT tableoid::regclass,* FROM customers;
SELECT * FROM customer_ind;
UPDATE customers SET cust_country ='jap' WHERE cust_id=2039;
SELECT * FROM customer_jap;

select ddlx_script('customers');
select ddlx_script('customer_jap');

-- test hash partitioning

-- test procedures
