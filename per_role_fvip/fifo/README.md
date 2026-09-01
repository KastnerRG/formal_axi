# FIFO role FVIP

This directory proves that a two-sided AXI FIFO preserves each channel while
the endpoint FVIP independently handles AXI protocol legality.

## Files

- [`axi_fifo_fvip.sv`](axi_fifo_fvip.sv) is the public aggregate. It instantiates
  one endpoint checker on each AXI side, creates their typed views, composes
  progress bounds across both FIFO crossings, composes each output AW/W skew
  capacity as the input bound plus FIFO depth, and instantiates the role
  checker.
- [`axi_fifo_role_fvip.sv`](axi_fifo_role_fvip.sv) connects one conservation
  tracker to each of AW, W, B, AR, and R. It depends only on the public views.
- [`fifo_tracker.sv`](fifo_tracker.sv) proves no phantom output, no overflow,
  no duplication/drop/reordering, payload integrity, and optional bounded
  progress for one ready/valid stream.

## Tracking

Each channel tracker lets formal select an arbitrary input handshake, stores
that payload, and tracks its rank until the matching output handshake. This
proves ordered forward delivery without an entry per FIFO slot; rank and
occupancy widths grow only logarithmically with depth. A scalar occupancy
counter proves inverse conservation and capacity. `ALLOW_BYPASS`
permits a same-cycle input/output match when the FIFO is empty; it should match
the DUT's fall-through behavior.

The role checker does not duplicate AXI rules and does not inspect endpoint
checker hierarchy. `DEPTH`, `FALL_THROUGH`, and the bounded-progress settings
are explicit proof-profile contracts rather than inferred DUT properties.

## Run

From the repository root:

```sh
make qverify ROLE=fifo VENDOR=zipcpu LEVEL=protocol
make qverify ROLE=fifo VENDOR=zipcpu LEVEL=full
```

Protocol level checks AXI channel legality and FIFO conservation. Full level
also enables AXI transaction association and ordering across channels.
