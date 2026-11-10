// slice_parameter_assigned_to_an_owned_binding_frees_the_callers_buffer: agora #545 — `= d p`, d an owned slice binding and p a parameter: d took the caller's buffer for its own and freed it at scope end, and the caller read and freed it again. The same through an `inout` slice given another parameter (`= p q`): two owners of one buffer.
// Closed: a slice that is only borrowed (a parameter, a field of a live value) is copied into the binding, field or `inout` slot that comes to own it — a buffer of its own, its elements copied (gen_clone_for_type).
// main (before this PR): AddressSanitizer, heap-use-after-free on `a` after `( f a )`; attempting double-free on `q` after `( setq d q )`.
// map: §7.6 | A2 | runs-clean | - | agora #545: a slice parameter assigned to an owned binding or an inout slice left two owners of the caller's buffer (UAF, double free)
@ f [i p → i {
    : ~ [i d [i | 1 2 3]
    = d p
    ^ . d length
}

@ setq inout [i p [i q → v { = p q }

@ setl inout [i p → v { = p [i | 3 4] }

@ main → i {
    : [i a [i | 5 6]
    ( nurl_println ( nurl_str_int ( f a ) ) )
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    : ~ [i d [i | 1 2]
    : [i q [i | 9 9 9]
    ( setq d q )
    ~ x d { ( nurl_println ( nurl_str_int x ) ) }
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    : ~ [i e [i | 1 2]
    ( setl e )
    ~ x e { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
