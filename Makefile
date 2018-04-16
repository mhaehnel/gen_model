NPB_MAJOR=3
NPB_MINOR=3
NPB_PATCH=1
NPB_VERSION=$(NPB_MAJOR).$(NPB_MINOR).$(NPB_PATCH)
NPB_VARIANT=OMP

NPB_BIN_EXT=.x

NPB_DIR=NPB$(NPB_VERSION)
NPB_FILE=$(NPB_DIR).tar.gz
NPB_URL=https://www.nas.nasa.gov/assets/npb/$(NPB_FILE)

NPB_VDIR=$(NPB_DIR)/NPB$(NPB_MAJOR).$(NPB_MINOR)-$(NPB_VARIANT)
NPB_BINDIR=$(NPB_VDIR)/bin

BENCHES=cg is dc ep mg ft sp bt lu ua
CLASSES=S W A B C D E

#Classes undefined in NPB
DISABLED_CLASSES_dc=C D E 
DISABLED_CLASSES_is=E 
DISABLED_CLASSES_ua=E
#Not compiling with gfortran
DISABLED_CLASSES_cg=E


$(foreach b,$(BENCHES),$(eval CLASSES_$(b)=$(filter-out $(DISABLED_CLASSES_$(b)),$(CLASSES))))

all: $(BENCHES)

define bench_submake =
  [ -f $(NPB_BINDIR)/$(1).$(2)$(NPB_BIN_EXT) ] || ( \
    echo "Building $(NPB_BINDIR)/$(1).$(2)$(NPB_BIN_EXT)" && \
    $$(MAKE) -C $(NPB_VDIR) $(1) CLASS=$(2) >/dev/null\
  ) &&
endef

define bench-rule =
  $1: $(NPB_DIR)
	@$(foreach c,$(CLASSES_$(1)),$(call bench_submake,$1,$(c))) true
endef

$(foreach b,$(BENCHES),$(eval $(call bench-rule,$(b))))

$(NPB_DIR): $(NPB_FILE)
	@echo "Extracting $<"
	tar -xaf $<
	cp $(NPB_VDIR)/config/NAS.samples/make.def.gcc_x86 $(NPB_VDIR)/config/make.def

$(NPB_FILE):
	@wget --no-verbose --show-progress -c $(NPB_URL) -O $(NPB_FILE)

clean:
	$(RM) $(NPB_FILE) 
	$(RM) -r $(NPB_DIR)
