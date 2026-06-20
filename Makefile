.DEFAULT_GOAL := qverify

SHELL := /bin/bash

# Select a soc-testbed implementation with these three variables:
#
#   ROLE   Functional role (for example: xbar, fifo, dma-register).
#   VENDOR Implementation provider under soc-testbed/axi/ip (for example:
#          zipcpu, pulp, or taxi).
#   IMPL   Wrapper implementation within that vendor and role (for example:
#          axixbar, axi_xbar, or taxi_axi_fifo).
#
# The default formally verifies ZIPCPU's full-AXI crossbar.  Examples:
#
#   make qverify
#   make qverify ROLE=xbar VENDOR=pulp IMPL=axi_xbar
#   make qverify ROLE=fifo VENDOR=taxi IMPL=taxi_axi_fifo
#   make qverify ROLE=dma-register VENDOR=zipcpu IMPL=axidma
#   make list
#   make sim ROLE=xbar VENDOR=zipcpu IMPL=axixbar
#
# list/sim/wave/init come directly from soc-testbed/common.mk and accept
# omitted or comma-separated filters.  qverify/compile select exactly one DUT
# and use the defaults below.

SOC_TESTBED := $(abspath soc-testbed)
PROT        ?= axi

# Parse the formal source closure for the default goal and formal targets, but
# not for common.mk's discovery/simulation/init targets.  This lets `make list`
# use empty/comma-separated filters without treating them as a path.
NEEDS_FORMAL := $(if $(filter qverify compile,$(MAKECMDGOALS)),1,$(if $(MAKECMDGOALS),,1))

ifeq ($(NEEDS_FORMAL),1)
ROLE   ?= xbar
VENDOR ?= zipcpu
IMPL   ?= axixbar
endif

# Reuse soc-testbed's shared init and implementation-dispatch targets instead
# of maintaining local copies.  Variables above are intentionally established
# first because common.mk declares only empty `?=` filter defaults.
SOC_TESTBED_COMMON := $(SOC_TESTBED)/common.mk
ifneq ($(wildcard $(SOC_TESTBED_COMMON)),)
include $(SOC_TESTBED_COMMON)
else
# Bootstrap a fresh checkout, where common.mk cannot be included until the
# outer soc-testbed gitlink itself has been initialized.
.PHONY: init
init:
	git submodule update --init soc-testbed
	$(MAKE) -C $(SOC_TESTBED) init
endif

ifeq ($(NEEDS_FORMAL),1)
SOC_TESTBED_AXI := $(SOC_TESTBED)/axi
# soc-testbed's include.mk files use ROOT_DIR to locate their dependencies.
ROOT_DIR := $(SOC_TESTBED_AXI)
IMPL_INCLUDE := $(ROOT_DIR)/ip/$(VENDOR)/impl_wrappers/$(ROLE)/$(IMPL)/include.mk

ifeq ($(wildcard $(IMPL_INCLUDE)),)
$(error No soc-testbed implementation ROLE=$(ROLE) VENDOR=$(VENDOR) IMPL=$(IMPL); run 'make list')
endif

# Reuse soc-testbed's PULP verification source definition and its selected
# implementation closure.  axi_test and rand_id_queue are class-based
# simulation drivers; formal uses the same AXI interfaces and clk_rst_gen but
# leaves protocol traffic symbolic, so those two sources are intentionally
# omitted from the formal compilation.
include $(ROOT_DIR)/vip.mk
VERILOG_SOURCES += $(filter-out %/axi_test.sv %/rand_id_queue.sv,$(VIP_SOURCES))
include $(IMPL_INCLUDE)

# AXI-Stream wrappers select a *_stream smoke-test top in their include.mk;
# this repository's protocol properties currently target memory-mapped AXI.
ifneq ($(filter %_stream,$(TOP)),)
$(error ROLE=$(ROLE) VENDOR=$(VENDOR) IMPL=$(IMPL) is AXI-Stream, which has no formal harness here)
endif

TOP       := tb_$(subst -,_,$(ROLE))
TB_SOURCE := tb/$(TOP).sv

ifeq ($(wildcard $(TB_SOURCE)),)
$(error Formal testbench $(TB_SOURCE) does not exist for ROLE=$(ROLE))
endif
endif

ODIR      ?= log
DOFILE    ?= qverify/run_formal.do
BASE_FLIST := $(abspath qverify/flist.f)
RUN_FLIST  := $(abspath $(ODIR)/flist.f)
COVER_VCD ?= 0

.PHONY: qverify compile clean help

define write_flist
	@mkdir -p $(ODIR)
	@{ \
	  printf '%s\n' '+incdir+$(abspath tb)' '+incdir+$(abspath .)' \
	    '+incdir+$(ROOT_DIR)/ip/pulp/axi/include'; \
	  printf '%s\n' $(VERILOG_SOURCES); \
	  printf '%s\n' '-f' '$(BASE_FLIST)' '$(abspath $(TB_SOURCE))'; \
	} > $(RUN_FLIST)
endef

qverify:
	rm -rf $(ODIR) work transcript vsim.wlf
	$(write_flist)
	TOP=$(TOP) FLIST=$(RUN_FLIST) qverify -c -od $(ODIR) -do $(DOFILE)
	@set -e; \
	dump_vcds() { \
	  section="$$1"; outdir="$$2"; \
	  mkdir -p "$(ODIR)/$$outdir"; \
	  awk -v section="$$section" 'BEGIN{on=0} \
	    $$0 ~ "^Targets " section " \\([0-9]+\\)" {on=1; next} \
	    on && /^-+/ {next} \
	    on && /^$$/ {on=0; next} \
	    on {print}' "$(ODIR)/formal_verify.rpt" | \
	  while IFS= read -r prop; do \
	    [ -n "$$prop" ] || continue; \
	    db="$(ODIR)/qwave_files/$$prop.db"; \
	    [ -f "$$db" ] || continue; \
	    script -q /dev/null -c \
	      "qwave2vcd -wavefile $$db -outfile $(ODIR)/$$outdir/$${prop}.vcd" \
	      > /dev/null 2>&1; \
	  done; \
	}; \
	dump_vcds "Fired with Warnings" error; \
	[ "$(COVER_VCD)" = "1" ] && dump_vcds Covered cover || true

compile:
	rm -rf $(ODIR) work transcript vsim.wlf
	$(write_flist)
	vlib work
	vlog -sv -suppress 2892 -f $(RUN_FLIST)

help:
	@sed -n '3,21p' Makefile

clean:
	rm -rf $(ODIR) work transcript vsim.wlf
