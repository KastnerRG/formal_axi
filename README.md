# Formal Verification of AXI IP

This repository contains composable AXI4 formal verification IP (FVIP),
role-specific checkers, and harnesses for implementations supplied by the
`soc-testbed` submodule. See [the FVIP guide](docs/README.md) for the checker
architecture and [the formal run guide](docs/formal_runs.md) for reproducible
profiles and prior results.

## FIFO quick start

Initialize the DUT submodule and enter the tool environment once:

```sh
make init
nix-shell
```

Run the ZIPCPU FIFO at either checking level:

```sh
make qverify ROLE=fifo VENDOR=zipcpu LEVEL=protocol
make qverify ROLE=fifo VENDOR=zipcpu LEVEL=full
```

`IMPL=sfifo` is selected automatically for this role/vendor pair. Equivalent
shortcuts are `make test-fifo-protocol` and `make test-fifo-full`.

- `LEVEL=protocol` checks AXI channel rules and FIFO channel conservation.
- `LEVEL=full` additionally checks cross-channel AR/R, AW/W, and AW/B
  transaction association, ordering, payload, and bounded progress.

The default invocation remains the full ZIPCPU crossbar proof:

```sh
make qverify
```

## Selection and output

- `ROLE` selects `tb/tb_<role>.sv`.
- `VENDOR` selects `soc-testbed/axi/ip/<vendor>`.
- `IMPL` selects that vendor's implementation wrapper.
- `LEVEL` is `protocol` or `full` and defaults to `full`.

Direct `make qverify` and `make compile` output goes to
`work/build/<role>_<vendor>_<impl>_<level>/`. Reproducible runners and mutation
suites retain their timestamped results in `work/runs/`. `make clean` removes
only `work/build/`; it preserves `work/runs/`.

Other implementation examples:

```sh
make list
make qverify ROLE=xbar VENDOR=pulp IMPL=axi_xbar LEVEL=full
make qverify ROLE=fifo VENDOR=taxi IMPL=taxi_axi_fifo LEVEL=protocol
make qverify ROLE=dma-register VENDOR=zipcpu IMPL=axidma LEVEL=full
```

Set `FORMAL_JOBS` to enlarge Questa's proof-engine portfolio on a suitable
host. For example:

```sh
make qverify ROLE=fifo VENDOR=zipcpu LEVEL=full \
  FORMAL_JOBS=32 FORMAL_TIMEOUT=20m
```

`init`, `list`, `sim`, and `wave` come from `soc-testbed/common.mk`. The root
`shell.nix` supplies Questa's host runtime dependencies; the Siemens tools and
license configuration still come from the user's shell setup.

## Documentation

- [FVIP architecture and file map](docs/README.md)
- [FIFO role checker](per_role_fvip/fifo/README.md)
- [FVIP mutation validation](fvip_validation/README.md)
- [Executed C0-C5 results](docs/c0_c5_execution.md)
- [Supported AXI4 profile](docs/axi4_mvp_profile.md)
