set flist $::env(FLIST)
set worklib [file join $::env(WORKDIR) work]

vlib $worklib
vmap work $worklib
vlog -sv -suppress 2892 -f $flist
formal compile -d tb_c6_public_pair_view_refinement

netlist targets -group c6_public_pair_view_refinement \
  *dut.g_txn.a_view_pair_aw* \
  *dut.g_txn.a_view_pair_w* \
  *dut.g_txn.c_view_pair_aw* \
  *dut.g_txn.c_view_pair_w* \
  *a_refine* \
  *c_refine*

# The complete endpoint necessarily elaborates assumptions for unrelated
# read/response observers.  Remove every assumption from this proof group and
# restore only the harness reset contract plus arbitrary pair-selector
# domains.  This makes the refinement independent of read, B,
# channel-protocol, DUT, target-routing, bounded-stall, and
# transaction-environment assumptions.
netlist assumes * -group c6_public_pair_view_refinement -remove
netlist assumes \
  a_initial_reset \
  a_reset_changes_only_at_posedge \
  a_reset_does_not_reassert \
  a_reset_releases \
  dut.g_txn.c_pair_w_payload_idx_range \
  dut.g_txn.s_pair_w_payload_idx_constant \
  dut.g_txn.u_txn.i_aw_w_tracker.c_watch_beat_range \
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_aw_occurrence \
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_once \
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_one \
  dut.g_txn.u_txn.i_aw_w_tracker.s_select_w_occurrence \
  dut.g_txn.u_txn.i_aw_w_tracker.s_watch_beat_constant \
  -group c6_public_pair_view_refinement \
  -add
formal verify -group c6_public_pair_view_refinement \
  -auto_constraint_off -jobs 8 -timeout 5m
formal generate waveforms

vmap work [file join [pwd] work]
exit
