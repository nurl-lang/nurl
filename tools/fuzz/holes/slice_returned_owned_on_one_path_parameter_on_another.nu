// slice_returned_owned_on_one_path_parameter_on_another: a function that hands back its own slice on one path (`^ s`, s bound to a literal) and its slice parameter on another (`^ p`) was marked as returning an owned slice: `__fn_ret_owned__` is one flag for the whole function, and the parameter's path never vetoed it. Its caller then freed the slice it had passed in, and the caller's own binding freed it again. The same held for a slice literal returned bare (`^ [i | 1 2]`) beside `^ p`, and for a closure inside the function whose `^ [i | 1]` set the enclosing function's flag.
// Closed: a slice return that is not the function's own (a parameter, a borrow) sets `__fn_ret_slice_mixed__`, which vetoes the owned answer at the function's end, as `__fn_ret_str_mixed__` does for a raw string; a closure body has flags of its own (agora #485's adversarial pass).
// …and that veto leaked `pick F a`'s own slice, taken for a lend (16 bytes under LSan with the stack scan off, agora #532). Now such a function answers per call (`@.__nurl_retdyn`, the hown slot every slice-returning function has) and the caller's binding owns the slice by that answer, in its owner flag (agora #540).
// main (before this PR): AddressSanitizer, attempting double-free on `pick T a`.
// map: §7.6 | A2 | runs-clean | - | agora #485: a slice returned owned on one path and a parameter on another was freed by the caller and by its owner (double free)
@ pick b c [i p → [i {
    ? c { ^ p } {}
    : [i s [i | 1 2]
    ^ s
}

@ pick_lit b c [i p → [i {
    ? c { ^ p } {}
    ^ [i | 3 4]
}

@ get [i p → [i {
    : ( @ [i ) mk \ → [i { ^ [i | 1] }
    ^ p
}

@ main → i {
    : [i a [i | 5 6]
    : [i r ( pick T a )
    : [i q ( pick F a )
    : [i t ( pick_lit T a )
    : [i u ( get a )
    ~ x r { ( nurl_println ( nurl_str_int x ) ) }
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    ~ x t { ( nurl_println ( nurl_str_int x ) ) }
    ~ x u { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
