set flist $::env(FLIST)
set top $::env(TOP)
set qlib $::env(QLIB)
vlib $qlib
vmap work $qlib
vlog -sv -suppress 2892 -f $flist
set compile_args [list -d $top]
if {[info exists ::env(ROLE)] && $::env(ROLE) eq "fifo"} {
    lappend compile_args -G "AXI_FIFO_DEPTH=$::env(FIFO_DEPTH)"
    lappend compile_args -G "AXI_FIFO_FALL_THROUGH=$::env(FIFO_FALL_THROUGH)"
    lappend compile_args -G "AXI_FIFO_TRACK_DEPTH=$::env(FIFO_TRACK_DEPTH)"
    lappend compile_args -G "AXI_FIFO_ALLOW_BYPASS=$::env(FIFO_ALLOW_BYPASS)"
    lappend compile_args -G "AXI_MAX_STALL=$::env(MAX_STALL)"
    lappend compile_args -G "AXI_MAX_OUTSTANDING=$::env(MAX_OUTSTANDING)"
    lappend compile_args -G "AXI_MAX_RESPONSE_DELAY=$::env(MAX_RESPONSE_DELAY)"
    lappend compile_args -G "AXI_MAX_WRITE_DATA_DELAY=$::env(MAX_WRITE_DATA_DELAY)"
    lappend compile_args -G "AXI_MAX_ROLE_DELAY=$::env(MAX_ROLE_DELAY)"
    lappend compile_args -G "AXI_ENABLE_BOUNDED_ENV=$::env(ENABLE_BOUNDED_ENV)"
}
formal compile {*}$compile_args
set verify_args [list -auto_constraint_off]
if {[info exists ::env(FORMAL_JOBS)] && $::env(FORMAL_JOBS) ne ""} {
    lappend verify_args -jobs $::env(FORMAL_JOBS)
}
if {[info exists ::env(FORMAL_TIMEOUT)] && $::env(FORMAL_TIMEOUT) ne ""} {
    lappend verify_args -timeout $::env(FORMAL_TIMEOUT)
}
formal verify {*}$verify_args
formal generate waveforms
exit
