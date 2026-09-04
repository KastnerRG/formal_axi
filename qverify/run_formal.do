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
if {[info exists ::env(ROLE)] && $::env(ROLE) eq "xbar"} {
    lappend compile_args -G "AXI_MAX_STALL=$::env(MAX_STALL)"
    lappend compile_args -G "AXI_MAX_OUTSTANDING=$::env(MAX_OUTSTANDING)"
    lappend compile_args -G "AXI_MAX_OUTPUT_OUTSTANDING=$::env(MAX_OUTPUT_OUTSTANDING)"
    lappend compile_args -G "AXI_MAX_OUTPUT_AW_AHEAD=$::env(MAX_OUTPUT_AW_AHEAD)"
    lappend compile_args -G "AXI_MAX_OUTPUT_W_AHEAD=$::env(MAX_OUTPUT_W_AHEAD)"
    lappend compile_args -G "AXI_MAX_RESPONSE_DELAY=$::env(MAX_RESPONSE_DELAY)"
    lappend compile_args -G "AXI_MAX_INPUT_RESPONSE_DELAY=$::env(MAX_INPUT_RESPONSE_DELAY)"
    lappend compile_args -G "AXI_MAX_WRITE_DATA_DELAY=$::env(MAX_WRITE_DATA_DELAY)"
    lappend compile_args -G "AXI_MAX_OUTPUT_WRITE_DATA_DELAY=$::env(MAX_OUTPUT_WRITE_DATA_DELAY)"
    lappend compile_args -G "AXI_MAX_ROLE_DELAY=$::env(MAX_ROLE_DELAY)"
    lappend compile_args -G "AXI_ENABLE_BOUNDED_ENV=$::env(ENABLE_BOUNDED_ENV)"
    lappend compile_args -G "AXI_ENABLE_ROLE=$::env(ENABLE_ROLE_FVIP)"
}
if {[info exists ::env(FORMAL_CONSTANTS)] && $::env(FORMAL_CONSTANTS) ne ""} {
    foreach constant_spec [split $::env(FORMAL_CONSTANTS) ","] {
        set separator [string first "=" $constant_spec]
        if {$separator < 1 || $separator == [expr {[string length $constant_spec] - 1}]} {
            error "FORMAL_CONSTANTS entries must be signal=value: $constant_spec"
        }
        set signal [string range $constant_spec 0 [expr {$separator - 1}]]
        set value [string range $constant_spec [expr {$separator + 1}] end]
        netlist constant $signal $value
    }
}
formal compile {*}$compile_args
set verify_args [list -auto_constraint_off]
set use_focused_group 0
if {[info exists ::env(FORMAL_TARGETS)] && $::env(FORMAL_TARGETS) ne ""} {
    set target_patterns [split $::env(FORMAL_TARGETS) ","]
    netlist targets -group focused {*}$target_patterns
    set use_focused_group 1
}
if {[info exists ::env(FORMAL_ASSUME_REMOVES)] && $::env(FORMAL_ASSUME_REMOVES) ne ""} {
    set remove_patterns [split $::env(FORMAL_ASSUME_REMOVES) ","]
    netlist assumes -group focused -remove {*}$remove_patterns
    set use_focused_group 1
}
if {[info exists ::env(FORMAL_ASSUMES)] && $::env(FORMAL_ASSUMES) ne ""} {
    set assume_patterns [split $::env(FORMAL_ASSUMES) ","]
    foreach assume_pattern $assume_patterns {
        if {[string first "*" $assume_pattern] >= 0} {
            netlist assumes -group focused -add $assume_pattern -also_match_asserts
        } else {
            netlist assumes -group focused -add $assume_pattern
        }
    }
    set use_focused_group 1
}
if {$use_focused_group} {
    lappend verify_args -group focused
}
if {[info exists ::env(FORMAL_JOBS)] && $::env(FORMAL_JOBS) ne ""} {
    lappend verify_args -jobs $::env(FORMAL_JOBS)
}
if {[info exists ::env(FORMAL_ENGINES)] && $::env(FORMAL_ENGINES) ne ""} {
    lappend verify_args -engines $::env(FORMAL_ENGINES)
}
if {[info exists ::env(FORMAL_TIMEOUT)] && $::env(FORMAL_TIMEOUT) ne ""} {
    lappend verify_args -timeout $::env(FORMAL_TIMEOUT)
}
formal verify {*}$verify_args
formal generate waveforms
exit
