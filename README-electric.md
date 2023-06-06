# Building for Electric

Electric maintains a fork of the original because we need a few tweaks 
on the upstream behaviour, specifically:

- Set column defaults within the `CREATE TABLE (...)` block, rather than via
  `ALTER TABLE .. SET DEFAULT` statements after the table creation.

- Define table constraints within the create table block too

Both of these are to support direct PostgreSQL -> SQLite command translation.
For example, SQLite does not support `ALTER TABLE .. SET DEFAULT` and we are
currently very strict about the migrations that we allow on electrified tables.

So it's best for our use case that tables are created in one shot, without
additional `ALTER TABLE` commands.

As PG versions progress it may be necessary to update these functions, hence
this fork which applies our patches in the `ddlx.sql` file which has
pre-processor statements for multiple PG version support.

## Generating Electric extension SQL

For the purposes of Electric, "extension" does not mean a postgresql extension.
Electric has its own extension mechanism based on simple SQL statements,
maintained via a basic migration system.

That extension mechanism expects everything to be written within the `electric`
pg schema. PostgreSQL allows for extensions to be relocated into any schema via
the built-in extension mechanism. Since we can't use that, we need to be able
to write our functions into a specific schema. 

So we have a pre-processor script that prefixes all function definitions and
calls with a `@schemaname@` prefix which we can replace when applying the sql
to the live pg database.

To generate a new "electrified" ddlx script, run the following:

```
make electric VERSION=$PG_VERSION
```

This will write a processed file to `electric-ddlx-$PG_VERSION.sql` in this
repo.

This file should be moved into the electric repo somewhere under 
`components/electric/lib/electric/postgres/extension/migrations/$TIMESTAMP/ddlx-$PG_VERSION.sql`.
See the existing ddlx migration version for a template.
