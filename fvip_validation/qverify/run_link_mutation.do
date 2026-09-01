set worklib [file join $::env(WORKDIR) work]
vlib $worklib
vmap work $worklib
vlog -sv -suppress 2892 -f fvip_validation/qverify/link_mutation.f
formal compile -d tb_link_mutation
formal verify -auto_constraint_off
formal generate waveforms
vmap work [file join [pwd] work]
exit
