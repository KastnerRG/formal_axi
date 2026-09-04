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
# The default formally verifies ZIPCPU's full-AXI crossbar. LEVEL selects the
# checker layer: protocol is the complete standalone endpoint contract
# (channel plus transaction) with no role knowledge; full composes that
# contract with the selected IP's cross-interface role properties.
# Examples:
#
#   make qverify
#   make qverify ROLE=fifo VENDOR=zipcpu LEVEL=protocol
#   make qverify ROLE=fifo VENDOR=zipcpu LEVEL=full
#   make test-fifo-protocol
#   make test-fifo-full
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
LEVEL  ?= full

DEFAULT_IMPL := axixbar
ifeq ($(ROLE)/$(VENDOR),fifo/zipcpu)
DEFAULT_IMPL := sfifo
else ifeq ($(ROLE)/$(VENDOR),fifo/pulp)
DEFAULT_IMPL := axi_fifo
else ifeq ($(ROLE)/$(VENDOR),fifo/taxi)
DEFAULT_IMPL := taxi_axi_fifo
else ifeq ($(ROLE)/$(VENDOR),xbar/pulp)
DEFAULT_IMPL := axi_xbar
else ifeq ($(ROLE)/$(VENDOR),dma-register/zipcpu)
DEFAULT_IMPL := axidma
endif
IMPL ?= $(DEFAULT_IMPL)

VALID_LEVELS := protocol full
ifneq ($(words $(LEVEL)),1)
$(error LEVEL must be one of: $(VALID_LEVELS))
endif
ifeq ($(filter $(LEVEL),$(VALID_LEVELS)),)
$(error LEVEL must be one of: $(VALID_LEVELS))
endif

override ENABLE_TRANSACTION_FVIP := 1
ifeq ($(LEVEL),protocol)
override ENABLE_ROLE_FVIP := 0
else
override ENABLE_ROLE_FVIP := 1
endif
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

ifeq ($(ROLE),fifo)
ROLE_FVIP_SOURCES := \
	per_role_fvip/fifo/axi_fifo_role_fvip.sv \
	per_role_fvip/fifo/axi_fifo_fvip.sv
else ifeq ($(ROLE),xbar)
ROLE_FVIP_SOURCES := \
	per_role_fvip/xbar/xbar_read_tracker.sv \
	per_role_fvip/xbar/xbar_write_tracker.sv \
	per_role_fvip/xbar/axi_xbar_role_fvip.sv \
	per_role_fvip/xbar/axi_xbar_fvip.sv
endif
endif

WORK_ROOT ?= $(abspath work)
BUILD_ROOT ?= $(WORK_ROOT)/build
ODIR      ?= $(BUILD_ROOT)/$(ROLE)_$(VENDOR)_$(IMPL)_$(LEVEL)
QLIB      ?= $(abspath $(ODIR)/questa_lib)
MODELSIM_INI ?= $(abspath $(ODIR)/modelsim.ini)
DOFILE    ?= $(abspath qverify/run_formal.do)
BASE_FLIST := $(abspath qverify/flist.f)
RUN_FLIST  := $(abspath $(ODIR)/flist.f)
COVER_VCD ?= 0
FIFO_DEPTH ?= 2
FIFO_FALL_THROUGH ?= 0
FIFO_TRACK_DEPTH ?= $(FIFO_DEPTH)
FIFO_ALLOW_BYPASS ?= $(FIFO_FALL_THROUGH)
MAX_STALL ?= 8
MAX_OUTSTANDING ?= 1
MAX_AW_AHEAD ?= 4
MAX_W_AHEAD ?= 4
MAX_OUTPUT_OUTSTANDING ?= 7
MAX_OUTPUT_AW_AHEAD ?= 7
ifeq ($(ROLE)/$(VENDOR)/$(IMPL),xbar/zipcpu/axixbar)
# One registered core AW plus one wrapper-skid AW can be overtaken by W.
# A depth-one input cannot fill both positions.
MAX_OUTPUT_W_AHEAD ?= $(shell sh -c 'n=$(MAX_OUTSTANDING); \
	[ $$n -lt 2 ] && echo $$n || echo 2')
else
MAX_OUTPUT_W_AHEAD ?= 1
endif
MAX_BURST_LEN ?= 8
MAX_RESPONSE_DELAY ?= 16
MAX_WRITE_DATA_DELAY ?= 16
ifeq ($(ROLE),xbar)
XBAR_MAX_RESPONSE_CONTENDERS := $(shell sh -c 'a=$$((2 * $(MAX_OUTSTANDING))); \
	b=$(MAX_OUTPUT_OUTSTANDING); [ $$a -lt $$b ] && echo $$a || echo $$b')
XBAR_RESPONSE_QUANTUM := $(shell sh -c 'echo $$(( \
	$(MAX_RESPONSE_DELAY) + $(MAX_STALL) + 1 ))')
XBAR_WRITE_DATA_QUANTUM := $(shell sh -c 'echo $$(( \
	$(MAX_WRITE_DATA_DELAY) + $(MAX_STALL) + 1 ))')
XBAR_FORWARD_ALLOWANCE := $(shell sh -c 'echo $$(( \
	$(XBAR_MAX_RESPONSE_CONTENDERS) * ($(MAX_STALL) + 2) ))')
MAX_INPUT_RESPONSE_DELAY ?= $(shell sh -c 'echo $$(( \
	2 * $(XBAR_FORWARD_ALLOWANCE) + \
	((( $(XBAR_MAX_RESPONSE_CONTENDERS) - 1) * $(MAX_BURST_LEN)) + 1) * \
	$(XBAR_RESPONSE_QUANTUM) ))')
MAX_OUTPUT_WRITE_DATA_DELAY ?= $(shell sh -c 'echo $$(( \
	$(XBAR_FORWARD_ALLOWANCE) + \
	((( $(MAX_OUTSTANDING) - 1) * $(MAX_BURST_LEN)) + 1) * \
	$(XBAR_WRITE_DATA_QUANTUM) ))')
XBAR_ROLE_READ_DELAY := $(shell sh -c 'echo $$(( \
	2 * $(XBAR_FORWARD_ALLOWANCE) + \
	$(XBAR_MAX_RESPONSE_CONTENDERS) * $(MAX_BURST_LEN) * \
	$(XBAR_RESPONSE_QUANTUM) ))')
XBAR_ROLE_WRITE_DELAY := $(shell sh -c 'echo $$(( \
	2 * $(XBAR_FORWARD_ALLOWANCE) + \
	$(MAX_OUTSTANDING) * $(MAX_BURST_LEN) * \
	$(XBAR_WRITE_DATA_QUANTUM) + \
	$(XBAR_MAX_RESPONSE_CONTENDERS) * $(XBAR_RESPONSE_QUANTUM) ))')
MAX_ROLE_DELAY ?= $(shell sh -c 'a=$(XBAR_ROLE_READ_DELAY); \
	b=$(XBAR_ROLE_WRITE_DELAY); c=$(MAX_INPUT_RESPONSE_DELAY); \
	d=$(MAX_OUTPUT_WRITE_DATA_DELAY); [ $$b -gt $$a ] && a=$$b; \
	[ $$c -gt $$a ] && a=$$c; [ $$d -gt $$a ] && a=$$d; echo $$a')
else
MAX_INPUT_RESPONSE_DELAY ?= $(shell sh -c 'echo $$(( \
	(2 * $(MAX_OUTSTANDING) - 1) * $(MAX_BURST_LEN) * \
	($(MAX_RESPONSE_DELAY) + $(MAX_STALL)) + 2 * $(MAX_STALL) ))')
MAX_OUTPUT_WRITE_DATA_DELAY ?= $(shell sh -c 'echo $$(( \
	($(MAX_OUTSTANDING) - 1) * $(MAX_BURST_LEN) * \
	($(MAX_WRITE_DATA_DELAY) + $(MAX_STALL)) + \
	$(MAX_WRITE_DATA_DELAY) + 2 * $(MAX_STALL) ))')
MAX_ROLE_DELAY ?= $(shell sh -c 'a=$(MAX_INPUT_RESPONSE_DELAY); \
	b=$(MAX_OUTPUT_WRITE_DATA_DELAY); [ $$a -gt $$b ] && echo $$a || echo $$b')
endif
ENABLE_BOUNDED_ENV ?= 1
FORMAL_TIMEOUT ?=
FORMAL_JOBS ?= 32
FORMAL_ENGINES ?=
FORMAL_TARGETS ?=
FORMAL_ASSUMES ?=
FORMAL_ASSUME_REMOVES ?=
FORMAL_CONSTANTS ?=

FORMAL_DEFINES := \
	+define+AXI_FVIP_FORMAL \
	+define+AXI_MAX_AW_AHEAD=$(MAX_AW_AHEAD) \
	+define+AXI_MAX_W_AHEAD=$(MAX_W_AHEAD) \
	+define+AXI_MAX_BURST_LEN=$(MAX_BURST_LEN) \
	+define+AXI_ENABLE_TRANSACTION_FVIP=$(ENABLE_TRANSACTION_FVIP) \
	+define+AXI_ENABLE_ROLE_FVIP=$(ENABLE_ROLE_FVIP)

ifeq ($(ROLE)/$(VENDOR)/$(IMPL),xbar/zipcpu/axixbar)
FORMAL_DEFINES += +define+AXI_XBAR_SCALAR_ENDPOINTS +define+AXI_ZIPCPU_XBAR_SCALAR_BRIDGE
endif

# soc-testbed shares these arguments with its Verilator flow.  Questa accepts
# the include paths but not Verilator's warning-policy switch.
FORMAL_EXTRA_ARGS := $(filter-out -Wno-fatal,$(EXTRA_ARGS))

.PHONY: qverify compile test-fifo-protocol test-fifo-full clean help

define write_flist
	@mkdir -p $(ODIR)
	@{ \
	  printf '%s\n' '+incdir+$(abspath tb)' '+incdir+$(abspath .)' \
	    '+incdir+$(ROOT_DIR)/ip/pulp/axi/include'; \
	  printf '%s\n' $(FORMAL_DEFINES) $(FORMAL_EXTRA_ARGS); \
	  printf '%s\n' $(VERILOG_SOURCES); \
	  printf '%s\n' '-f' '$(BASE_FLIST)'; \
	  printf '%s\n' $(foreach source,$(ROLE_FVIP_SOURCES),'$(abspath $(source))'); \
	  printf '%s\n' '$(abspath $(TB_SOURCE))'; \
	} > $(RUN_FLIST)
endef

qverify:
	rm -rf $(ODIR)
	rm -f transcript vsim.wlf
	$(write_flist)
	cd $(ODIR) && vmap -c
	MODELSIM=$(MODELSIM_INI) TOP=$(TOP) ROLE=$(ROLE) FLIST=$(RUN_FLIST) QLIB=$(QLIB) \
	  FIFO_DEPTH=$(FIFO_DEPTH) FIFO_FALL_THROUGH=$(FIFO_FALL_THROUGH) \
	  FIFO_TRACK_DEPTH=$(FIFO_TRACK_DEPTH) FIFO_ALLOW_BYPASS=$(FIFO_ALLOW_BYPASS) \
	  MAX_STALL=$(MAX_STALL) MAX_OUTSTANDING=$(MAX_OUTSTANDING) \
	  MAX_OUTPUT_OUTSTANDING=$(MAX_OUTPUT_OUTSTANDING) \
	  MAX_OUTPUT_AW_AHEAD=$(MAX_OUTPUT_AW_AHEAD) \
	  MAX_OUTPUT_W_AHEAD=$(MAX_OUTPUT_W_AHEAD) \
	  MAX_RESPONSE_DELAY=$(MAX_RESPONSE_DELAY) \
	  MAX_INPUT_RESPONSE_DELAY=$(MAX_INPUT_RESPONSE_DELAY) \
	  MAX_WRITE_DATA_DELAY=$(MAX_WRITE_DATA_DELAY) \
	  MAX_OUTPUT_WRITE_DATA_DELAY=$(MAX_OUTPUT_WRITE_DATA_DELAY) \
	  MAX_ROLE_DELAY=$(MAX_ROLE_DELAY) \
	  ENABLE_BOUNDED_ENV=$(ENABLE_BOUNDED_ENV) ENABLE_ROLE_FVIP=$(ENABLE_ROLE_FVIP) \
	  FORMAL_TIMEOUT=$(FORMAL_TIMEOUT) FORMAL_JOBS=$(FORMAL_JOBS) \
	  FORMAL_ENGINES='$(FORMAL_ENGINES)' \
	  FORMAL_TARGETS='$(FORMAL_TARGETS)' \
	  FORMAL_ASSUMES='$(FORMAL_ASSUMES)' \
	  FORMAL_ASSUME_REMOVES='$(FORMAL_ASSUME_REMOVES)' \
	  FORMAL_CONSTANTS='$(FORMAL_CONSTANTS)' \
	  qverify -c -od $(ODIR) -do $(DOFILE)
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
	      < /dev/null > /dev/null 2>&1; \
	  done; \
	}; \
	dump_vcds "Fired with Warnings" error; \
	[ "$(COVER_VCD)" = "1" ] && dump_vcds Covered cover || true

compile:
	rm -rf $(ODIR)
	rm -f transcript vsim.wlf
	$(write_flist)
	cd $(ODIR) && vmap -c
	vlib $(QLIB)
	vmap -modelsimini $(MODELSIM_INI) work $(QLIB)
	vlog -modelsimini $(MODELSIM_INI) -sv -suppress 2892 -f $(RUN_FLIST)

test-fifo-protocol:
	$(MAKE) qverify ROLE=fifo VENDOR=zipcpu IMPL=sfifo LEVEL=protocol

test-fifo-full:
	$(MAKE) qverify ROLE=fifo VENDOR=zipcpu IMPL=sfifo LEVEL=full

help:
	@sed -n '3,27p' Makefile

clean:
	rm -rf $(BUILD_ROOT)
	rm -f transcript vsim.wlf
