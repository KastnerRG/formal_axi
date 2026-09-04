set flist $::env(FLIST)
set worklib [file join $::env(WORKDIR) work]

vlib $worklib
vmap work $worklib
vlog -sv -suppress 2892 -f $flist
formal compile -d tb_pair_summary_refinement

netlist targets -group summary_refinement \
  *a_tracker_aw_summary_capture* \
  *c_aw_summary_capture* \
  *a_refine* \
  *c_refine*
formal verify -group summary_refinement -auto_constraint_off -jobs 8 -timeout 2m
formal generate waveforms

vmap work [file join [pwd] work]
exit
