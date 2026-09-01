# FVIP validation

This directory verifies the production checkers with legal and deliberately
broken models. Its exact bounded scoreboards are validation oracles, not part
of the deployable AXI/FIFO proof model.

## Layout

- `reference_models/fifo_oracle.sv`: exact FIFO queue used to cross-check the
  selected-occurrence production tracker.
- `reference_models/axi_transaction_oracle.sv`: exact bounded AXI request and
  response queues used to cross-check transaction tracking.
- `tb/tb_link_mutation.sv`: good and bad endpoint models for polarity,
  stability, and bounded READY checks.
- `tb/tb_fifo_mutation.sv`: legal FIFO plus phantom, drop, duplicate, corrupt,
  reorder, and deadlock mutations.
- `tb/tb_transaction_mutation.sv`: legal traffic plus orphan, ID, WLAST,
  WSTRB, ordering, duplication, rank-compaction, and progress scenarios.
- `qverify/`: validation-only source lists and formal command files.
- `tools/`: reproducible runners and CSV score gates.

The deployable checkers remain in `axi_sva/our/` and `per_role_fvip/`. The
transaction and FIFO trackers use selected-occurrence/rank tracking plus scalar
global occupancy; they contain no array indexed by outstanding transactions.

Run the suites from the repository root:

```sh
fvip_validation/tools/run_link_mutations.sh
fvip_validation/tools/run_fifo_mutations.sh
fvip_validation/tools/run_transaction_mutations.sh
```

Each runner writes a timestamped score and formal artifacts below
`work/runs/`. Set `ODIR` to choose a different new directory.

The FIFO suite compares the selected-occurrence tracker directly with
`fifo_oracle.sv`.
The transaction suite instantiates `axi_transaction_oracle.sv` beside the
smart checker. Both models detect the transaction-safety mutations. The smart
endpoint policy additionally detects missing R, W, and B progress; those are
bounded-profile failures rather than base AXI safety failures.
The link suite exercises payload stability and DUT-owned READY starvation in
both Manager and Subordinate endpoint polarities.

Selected-occurrence properties are universal when used as assertions: the
formal selector may choose any faulty occurrence. A selector-dependent
assumption cannot constrain every occurrence, however. Production endpoint
FVIPs therefore instantiate deterministic bounded environment contracts from
`axi_fvip_env_contract.sv`. Role harnesses do not duplicate AXI legality.
