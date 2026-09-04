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
| [`pkg_axi_fvip.sv`](../axi_sva/our/pkg_axi_fvip.sv) | Local burst-geometry helpers layered on the canonical `axi_pkg` constants and widths. |
| [`axi_channel_fvip.sv`](../axi_sva/our/axi_channel_fvip.sv) | Intra-channel AXI4 rules, ordered like the specification. |
| [`axi_fvip_env_contract.sv`](../axi_sva/our/axi_fvip_env_contract.sv) | Universal bounded contracts for environment-owned transactions. |
| [`axi_read_tracker.sv`](../axi_sva/our/axi_read_tracker.sv) | Thin read shell: shared selected AR occurrence plus R-beat/RLAST and response-progress policy. |
| [`axi_pair_tracker.sv`](../axi_sva/our/axi_pair_tracker.sv) | Thin AXI shell around the shared two-sided AW/W occurrence core, adding WLAST/WSTRB and W-progress policy. |
| [`axi_write_tracker.sv`](../axi_sva/our/axi_write_tracker.sv) | Thin write shell: selected-AW W distance, completed-write credit, and a shared ordered B occurrence. |
| [`axi_transaction_fvip.sv`](../axi_sva/our/axi_transaction_fvip.sv) | Connects the three transaction trackers and enforces global outstanding bounds. |
| [`stream_trackers.sv`](../axi_sva/our/stream_trackers.sv) | Shared occurrence/rank/occupancy and two-sided ordered-pair cores, plus thin FIFO and routed-stream policy shells. |
| [`axi_fvip_txn_view_if.sv`](../axi_sva/our/axi_fvip_txn_view_if.sv) | Parameter-exact live channel vectors and flat selected-transaction state shared with role checkers. |
| [`axi_fvip.sv`](../axi_sva/our/axi_fvip.sv) | Standalone endpoint aggregate; exposes `manager_axi_fvip` or `subordinate_axi_fvip`. |

The legacy `m_sva_wrap` and `s_sva_wrap` adapters have been removed.
[`qverify/flist.f`](../qverify/flist.f) uses
[`axi_fvip_endpoints.sv`](../axi_sva/axi_fvip_endpoints.sv) solely to compile
`manager_axi_fvip` and `subordinate_axi_fvip` from the shared endpoint source; that source owns
the compile-time polarity mapping. Role aggregates
instantiate those modules directly; the DMA harness directly instantiates
`subordinate_axi_fvip`.

## Role and validation files

Role-specific FVIP lives under [`per_role_fvip/`](../per_role_fvip/). The FIFO
and 2x2 crossbar implementations and their parameters are documented in
[`per_role_fvip/fifo/README.md`](../per_role_fvip/fifo/README.md) and
[`per_role_fvip/xbar/README.md`](../per_role_fvip/xbar/README.md). Exact bounded
reference queues and mutation campaigns are intentionally separate under
[`fvip_validation/`](../fvip_validation/README.md); they validate the production
checkers but are not part of the sign-off proof model.

## Checking levels

- `LEVEL=protocol`: the complete standalone channel and transaction endpoint
  contract on every exposed AXI interface, with no role hierarchy.
- `LEVEL=full`: the same endpoint contract plus the selected IP's role
  properties. For a FIFO these prove conservation, order, and preservation;
  for a crossbar they prove route, transformation, and response return.

Formal runs use Questa's completed vacuity analysis as the assertion-trigger
reachability audit. Covers are added for useful scenarios, or when vacuity
cannot decide—not mechanically for every implication. The generated
`vacuity_status.csv` records the result for each enabled assertion; optional
properties absent from the selected level/profile are feature-disabled.

Build artifacts live in `work/build/`; retained formal and validation runs live
in `work/runs/`.
