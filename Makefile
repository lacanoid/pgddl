PG_CONFIG = pg_config
PKG_CONFIG = pkg-config

extension_version = 0.10

EXTENSION = ddlx
DATA_built = ddlx--$(extension_version).sql

REGRESS = init role type class fdw tsearch misc script 
REGRESS_OPTS = --inputdir=test

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

ddlx--$(extension_version).sql: ddlx.sql
	cat $^ >$@
