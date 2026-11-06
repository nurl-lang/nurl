// closure_falloff_inner_closure_copies_captured_handle_runs_clean: a closure body whose tail expression without `^` is an inner closure literal owns what it captures.
// Closed: `__is_fall_value_stmt` and `__src_operand_end` recognize a tail closure literal (`\ params → ret { … }`), routing it through `gen_ret` so `clo_returned` is true and the inner closure's environment owns a copy of the outer local's handle instead of a dangling bitwise copy (agora #473).
// main a3be3e7c: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.5 | A2 | runs-clean | - | agora #473: a fall-off inner closure literal without `^` owns its captured local in its environment
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ ( @ String ) ) mk \ → ( @ String ) {
        : String kept ( string_from `hello world from outer closure local on heap` )
        \ → String { ^ kept }
    }
    : ( @ String ) inner ( mk )
    : String got ( inner )
    ( nurl_println ( string_data got ) )
    ^ 0
}
