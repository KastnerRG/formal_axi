# AXI4 formal VIP profile

The enabled baseline is **AMBA AXI4 Full, Issue H.c, normal transactions over
VALID/READY transport**.  It is not an AXI5 profile.  `AWATOP` is present in the
shared PULP interface for compatibility but is constrained to zero.  Exclusive
accesses (`AxLOCK=1`) and `EXOKAY` responses are disabled until the exclusive
profile is implemented.

The default configured bounds are four outstanding reads, four outstanding
writes, four completed W bursts ahead of AW, four AW requests ahead of completed
W bursts, and eight beats per burst.  These are explicit model-capacity
contracts, not limits imposed by AXI4. The production DUT-guarantee trackers
store selected transaction summaries, bounded relative ranks, scalar global
counts, and one arbitrary WSTRB beat sample; no guarantee array is dimensioned
by outstanding or burst limits. Deterministic environment contracts do use
bounded lifecycle arrays so assumptions constrain every occurrence, but they
produce no DUT proof result. Exact DUT comparison scoreboards exist only in
`fvip_validation/reference_models/`.

The AXI FVIP exposes typed capacity and progress parameters. `MAX_OUTSTANDING`
bounds transaction-model state. `MAX_STALL` bounds READY availability after
VALID: it is assumed when READY is environment-driven and asserted when READY
is DUT-driven.

`MAX_RESPONSE_DELAY` is an opt-in bounded-progress policy inside every
endpoint FVIP. It bounds availability of the first selected R beat after AR,
each later R beat after the previous beat, and B after the matching AW+W
completion. A visible stalled beat satisfies response availability;
`MAX_STALL` separately bounds its acceptance. The rule is assumed for an
environment Subordinate and asserted for a DUT Subordinate.

`MAX_WRITE_DATA_DELAY` is distinct because AW/W skew bounds capacity, not
time. For DUT Managers it asserts bounded availability of every required W
beat after AW. The deterministic environment contract uses the stronger
simple form that the complete matching W burst joins within the bound.

In a role aggregate, the configured response/write-data values constrain the
outer environment where those events originate.  The opposite, DUT-owned
endpoint includes the two cross-interface role traversals, so the FIFO
aggregate checks it with the explicit compositional bound
`outer delay + 2 * MAX_ROLE_DELAY`.  This keeps each standalone endpoint
honest without incorrectly requiring a pipelined DUT to meet the same latency
as its downstream environment.

Environment assumptions use deterministic bounded lifecycle models, because
a selected-occurrence assumption can avoid a bad occurrence. DUT guarantees
continue to use constant-state selected trackers. Setting
`ENABLE_BOUNDED_ENV=0` removes the READY, response, write-data, and FIFO-role
progress policies. Any run with these enabled is a bounded-profile proof.

Selected-occurrence/rank properties are universal when asserted, because the
formal selector can choose any faulty occurrence. They are not by themselves
universal environment constraints: a selector-dependent assumption can choose
a different occurrence. The endpoint FVIP therefore supplies deterministic
bounded source and subordinate lifecycle contracts for the environment side.

Property prefixes classify their role:

| Prefix | Class |
|---|---|
| `a_` on a source connected to the environment | environment assumption |
| `a_` on a source driven by the DUT | interface guarantee |
| `x_` | role-dependent cross-channel assumption or guarantee |
| `c_profile_`, `c_max_` | configuration assumption |
| `p_` | opt-in bounded-progress policy |
| `c_` otherwise | reachability cover |

The wrappers exchange source/destination polarity, so the same logical rule is
an assumption at an unconstrained external agent and a guarantee at the DUT
interface.  The checked rule inventory is `docs/axi4_our_status.csv`; it was audited
against the local Issue H.c PDF and extracted text.  Rules excluded by the MVP
remain visible as `not applicable`, rather than being counted as proofs.
