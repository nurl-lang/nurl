// slice_from_a_function_compiled_later_released: a slice handed back by a function whose body comes later in the file (`( mk 3 )` in main, `@ mk` below it) was taken for a lend — `__ret_owned` is set when mk's body ends — and never freed.
// Closed: the binding's owner flag takes the module-end answer (`@.__nurl_retown`, agora #540), the one handles already used for a callee not compiled yet.
// main ad960922: LeakSanitizer (use_stacks=0): 16 bytes leaked.
// map: §7.6 | A2 | runs-clean | - | agora #540: a slice from a function compiled later was taken for a lend and leaked
@ main → i {
    : [i q ( mk 3 )
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

@ mk i n → [i {
    : [i s [i | 1 2]
    ^ s
}
