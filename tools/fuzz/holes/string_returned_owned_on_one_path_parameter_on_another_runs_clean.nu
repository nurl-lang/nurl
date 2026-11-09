// string_returned_owned_on_one_path_parameter_on_another_runs_clean: the raw-string shape of agora #540's slice probe — a function handing back its own string on one path (a binding, or a call's result) and its string parameter on another. A string answers per call (the return proof, nurl_ret_owned_set), so each caller frees exactly the one it was given.
// Kept as a twin of slice_returned_owned_on_one_path_parameter_on_another: the slice fix answers per call the same way.
// main ad960922: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #540: raw strings answer per call whether a return was the function's own
$ `stdlib/core/io.nu`

@ pick b c s p → s {
    ? c { ^ p } {}
    : s t ( nurl_str_cat `ab` `cd` )
    ^ t
}

@ pick_call b c s p → s {
    ? c { ^ p } {}
    ^ ( nurl_str_cat `ef` `gh` )
}

@ main → i {
    : s a ( nurl_str_cat `x` `y` )
    : s r ( pick T a )
    : s q ( pick F a )
    : s t ( pick_call T a )
    : s u ( pick_call F a )
    ( puts r ) ( puts q ) ( puts t ) ( puts u )
    ^ 0
}
