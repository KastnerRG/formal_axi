# FVIP architecture

The production FVIP has two boundaries. An endpoint checker proves or assumes
AXI legality according to signal ownership. A role checker then relates two
already-legal endpoints to prove what a FIFO, crossbar, or other component must
preserve. Role checkers consume the public transaction view and do not reach
into endpoint internals.

## Tracking method

Transaction properties use selected-occurrence/rank tracking. Formal chooses
one arbitrary accepted transaction; the checker stores only that transaction
and its relative rank until completion. Because an assertion must hold for
every possible selector choice, this proves every occurrence without an array
of all outstanding transactions. Scalar counters separately enforce global
occupancy bounds, and an arbitrary beat selector checks burst payload details.

The same selector cannot safely constrain an environment: the solver could
avoid selecting an illegal occurrence. Deterministic environment contracts
therefore constrain every environment-owned transaction. FIFO conservation
uses the same selected-occurrence idea for data/order plus a scalar occupancy
counter for phantom, overflow, and duplication checks.

## Endpoint files

| File | Purpose |
| --- | --- |
| [`pkg_axi_fvip.sv`](../axi_sva/our/pkg_axi_fvip.sv) | Shared AXI enums and small geometry helpers. |
| [`axi_switch_fvip.svh`](../axi_sva/our/axi_switch_fvip.svh) | Selects Manager/Subordinate module names and assume/assert polarity. |
| [`axi_channel_fvip.sv`](../axi_sva/our/axi_channel_fvip.sv) | Intra-channel AXI4 rules, ordered like the specification. |
| [`axi_fvip_env_contract.sv`](../axi_sva/our/axi_fvip_env_contract.sv) | Universal bounded contracts for environment-owned transactions. |
| [`axi_read_tracker.sv`](../axi_sva/our/axi_read_tracker.sv) | Selected AR occurrence, same-ID rank, R beats, RID/RLAST, and response progress. |
| [`axi_pair_tracker.sv`](../axi_sva/our/axi_pair_tracker.sv) | Selected AW/W association in either arrival order, WLAST/WSTRB, and W progress. |
| [`axi_write_tracker.sv`](../axi_sva/our/axi_write_tracker.sv) | Selected AW through its paired W burst and ordered BID/B response. |
| [`axi_transaction_fvip.sv`](../axi_sva/our/axi_transaction_fvip.sv) | Connects the three transaction trackers and enforces global outstanding bounds. |
| [`axi_fvip_txn_view_if.sv`](../axi_sva/our/axi_fvip_txn_view_if.sv) | Typed public boundary containing live AXI records and selected transaction state. |
| [`axi_fvip.sv`](../axi_sva/our/axi_fvip.sv) | Standalone endpoint aggregate; exposes `m_axi_fvip` or `s_axi_fvip`. |

[`m_sva_wrap.sv`](../axi_sva/m_sva_wrap.sv) and
[`s_sva_wrap.sv`](../axi_sva/s_sva_wrap.sv) adapt the endpoint checkers to the
repository harnesses. [`qverify/flist.f`](../qverify/flist.f) is the production
source order.

## Role and validation files

Role-specific FVIP lives under [`per_role_fvip/`](../per_role_fvip/). The FIFO
implementation and its parameters are documented in
[`per_role_fvip/fifo/README.md`](../per_role_fvip/fifo/README.md). Exact bounded
reference queues and mutation campaigns are intentionally separate under
[`fvip_validation/`](../fvip_validation/README.md); they validate the production
checkers but are not part of the sign-off proof model.

## Checking levels

- `LEVEL=protocol`: endpoint channel legality plus role channel conservation.
- `LEVEL=full`: protocol level plus cross-channel transaction tracking and
  configured bounded-progress checks.

Formal runs use Questa's completed vacuity analysis as the assertion-trigger
reachability audit. Covers are added for useful scenarios, or when vacuity
cannot decide—not mechanically for every implication. The generated
`vacuity_status.csv` records the result for each enabled assertion; optional
properties absent from the selected level/profile are feature-disabled.

Build artifacts live in `work/build/`; retained formal and validation runs live
in `work/runs/`.
