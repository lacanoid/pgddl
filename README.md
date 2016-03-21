DDL extractor functions  for PostgreSQL
=======================================

A set of in-database SQL functions for decompiling objects in a PostgreSQL database to DDL (data definition language).
Kind of SQL implementation of pg_dump (which is external tool) inside the database itself.
Plus you can use it with any PostgreSQL compatible client which support running SQL queries.
It's obviously not going to replace pg_dump any time soon, but perhaps it can provide
some common ground for better tooling in the future.

Rationale
1. higher level grouping of available functions
2. current ddl generation is hard
3. support in more tools
4. clean slate
5. you have to write all this hairy stuff in your software
6. problems with versions

pgdump
------

psql
----
Command line client psql contains lots of packaged SQL for handling metadata 
mainly to support code comple

pgAdmin3
--------
PgAdmin3 DDL generation and schema handling code is an interesting 
mix of wxWidgets GUI toolkit (C++) and SQL.


This will hopefully help to keep SQL code in one place.

...

This is an extension for PostgreSQL that provides a `uri` data type.
Advantages over using plain `text` for storing URIs include:

- URI syntax checking
- functions for extracting URI components
- human-friendly sorting

The actual URI parsing is provided by the
[uriparser](http://uriparser.sourceforge.net/) library, which supports
URI syntax as per [RFC 3986](http://tools.ietf.org/html/rfc3986).

Note that this might not be the right data type to use if you want to
store user-provided URI data, such as HTTP referrers, since they might
contain arbitrary junk.

Installation
------------

You need to have the above-mentioned `uriparser` library installed.
It is included in many operating system distributions and package
management systems.  `pkg-config` will be used to find it.  I
recommend at least version 0.8.0.  Older versions will also work, but
they apparently contain some bugs and might fail to correctly accept
or reject URI syntax corner cases.  This is mainly a problem if your
application needs to be robust against junk input.

To build and install this module:

    make
    make install

or selecting a specific PostgreSQL installation:

    make PG_CONFIG=/some/where/bin/pg_config
    make PG_CONFIG=/some/where/bin/pg_config install

And finally inside the database:

    CREATE EXTENSION uri;

Using
-----

This module provides a data type `uri` that you can use like a normal
type.  For example:

```sql
CREATE TABLE links (
    id int PRIMARY KEY,
    link uri
);

INSERT INTO links VALUES (1, 'https://github.com/petere/pgddl');
```

A number of functions are provided to extract parts of a URI:

- `uri_scheme(uri) returns text`

    Extracts the scheme of a URI, for example `http` or `ftp` or
    `mailto`.

- `uri_userinfo(uri) returns text`

    Extracts the user info part of a URI.  This is normally a user
    name, but could also be of the form `username:password`.  If the
    URI does not contain a user info part, then this will return null.

- `uri_host(uri) returns text`

    Extracts the host of a URI, for example `www.example.com` or
    `192.168.0.1`.  (For IPv6 addresses, the brackets are not included
    here.)  If there is no host, the return value is null.

- `uri_host_inet(uri) returns inet`

    If the host is a raw IP address, then this will return it as an
    `inet` datum.  Otherwise (not an IP address or no host at all),
    the return value is null.

- `uri_port(uri) returns integer`

    Extracts the port of a URI as an integer, for example `5432`.  If
    no port is specified, the return value is null.

- `uri_path(uri) returns text`

    Extracts the path component of a URI.  Logically, a URI always
    contains a path.  The return value can be an empty string but
    never null.

- `uri_path_array(uri) returns text[]`

    Returns the path component of a URI as an array, with the path
    split at the slash characters.  This is probably not as useful as
    the `uri_path` function, but it is provided here because the
    `uriparser` library exposes it.

- `uri_query(uri) returns text`

    Extracts the query part of a URI (roughly speaking, everything
    after the `?`).  If there is no query part, returns null.

- `uri_fragment(uri) returns text`

    Extracts the fragment part of a URI (roughly speaking, everything
    after the `#`).  If there is no fragment part, returns null.

Other functions:

- `uri_normalize(uri) returns uri`

    Performs syntax-based normalization of the URI.  This includes
    case normalization, percent-encoding normalization, and removing
    redundant `.` and `..` path segments.  See
    [RFC 3986 section 6.2.2](http://tools.ietf.org/html/rfc3986#section-6.2.2)
    for the full details.

    Note that this module (and similar modules in other programming
    languages) compares URIs for equality in their original form,
    without normalization.  If you want to consider distinct URIs
    without regard for mostly irrelevant syntax differences, pass them
    through this function.

- `uri_escape(text) returns text`

    Percent-encodes all unreserved characters from the text. This can
    be useful for constructing URIs from strings.

