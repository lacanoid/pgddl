PG_CONFIG    = pg_config
PKG_CONFIG   = pkg-config

EXTENSION    = ddlx
EXT_VERSION  = 0.12
VTESTS       = $(shell bin/tests ${VERSION})

DATA_built   = ddlx--$(EXT_VERSION).sql

REGRESS      = init role type class fdw tsearch misc script ${VTESTS}
#REGRESS      = ($shell bin/tests)
REGRESS_OPTS = --inputdir=test

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(DATA_built): ddlx.sql
	@echo "Building extension version" $(EXT_VERSION) "for Postgres version" $(VERSION)
	VERSION=${VERSION} ./bin/pgsqlpp $^ >$@
