\pset null _null_
\pset format unaligned

SET client_min_messages = warning;
SET ROLE postgres;

-- row level security
create extension "uuid-ossp" ;
create table if not exists items (
  id uuid default uuid_generate_v4() not null primary key,
  value text,
  acl_read uuid[] default array[]::uuid[],
  acl_write uuid[] default array[]::uuid[]
);
-- e.g. ('f386...5e99', 'I row and therefore I am', {'eac6...f6c9'}, {'0fdc...947f'})
create policy item_owner
on items
for all
to postgres
using (
  items.acl_read && regexp_split_to_array(current_setting('jwt.claims.roles'), ',')::uuid[]
  or items.acl_write && regexp_split_to_array(current_setting('jwt.claims.roles'), ',')::uuid[]
)
with check (
  items.acl_write && regexp_split_to_array(current_setting('jwt.claims.roles'), ',')::uuid[]
);

-- create index read_permissions_index on items using gin(acl_read);
-- create index write_permissions_index on items using gin(acl_write);

select ddlx_script('items');
