set mutation $::env(MUTATION)
set flist $::env(FLIST)
set worklib [file join $::env(WORKDIR) work]
vlib $worklib
vmap work $worklib
vlog -sv -suppress 2892 -f $flist
formal compile -d tb_transaction_mutation -G MUTATION=$mutation
formal verify -auto_constraint_off
formal generate waveforms
vmap work [file join [pwd] work]
exit
