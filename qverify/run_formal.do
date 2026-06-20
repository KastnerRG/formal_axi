set flist $::env(FLIST)
set top $::env(TOP)
vlib work
vlog -sv -suppress 2892 -f $flist
formal compile -d $top
formal verify -auto_constraint_off
formal generate waveforms
exit
