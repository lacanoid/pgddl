PG_CONFIG = pg_config
PKG_CONFIG = pkg-config

extension_version = 0.4

EXTENSION = ddl
DATA_built = ddl--$(extension_version).sql

REGRESS = init test
REGRESS_OPTS = --inputdir=test

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

ddl--$(extension_version).sql: ddl.sql
	cat $^ >$@
