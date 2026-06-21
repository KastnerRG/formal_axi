# Formal Verification of AXI IP

The DUTs and their generic wrappers come from the `soc-testbed` submodule.
The formal harnesses reuse its PULP AXI interfaces and clock/reset generator.

ZIPCPU's full AXI crossbar is the default:

```sh
make init
nix-shell
make qverify
```

The root `shell.nix` supplies Questa's host-side `libXau` and `csh` runtime
dependencies. The Siemens tools and license configuration continue to come
from the user's shell setup.

Select another implementation with the same three-part naming used by
soc-testbed:

```sh
make list
make qverify ROLE=xbar VENDOR=pulp IMPL=axi_xbar
make qverify ROLE=fifo VENDOR=taxi IMPL=taxi_axi_fifo
make qverify ROLE=dma-register VENDOR=zipcpu IMPL=axidma
```

`init`, `list`, `sim`, and `wave` are inherited from soc-testbed's shared
`common.mk`, including selective submodule initialization, comma-separated
filters, and AXI-Stream role naming:

```sh
make init
make list ROLE=xbar,xbar_stream
make sim ROLE=xbar VENDOR=zipcpu IMPL=axixbar
make wave ROLE=fifo VENDOR=taxi IMPL=taxi_axi_fifo
```

- `ROLE` is the functional category and selects `tb/tb_<role>.sv`.
- `VENDOR` selects `soc-testbed/axi/ip/<vendor>`.
- `IMPL` selects the vendor's wrapper and RTL source closure for that role.

`make compile` performs a Questa compile without running formal. Formal reports
and optional VCDs are written under `log/` by default.
