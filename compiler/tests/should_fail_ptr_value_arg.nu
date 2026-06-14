// should_fail_ptr_value_arg.nu — the argument type checker must reject a
// `*T` pointer passed where a `T` value parameter is expected (the
// dchannel / SWIM silent-miscompile class). Without the check this
// compiled to garbage (the callee read fields off the pointer's bits).

: Box { i v }

@ take Box b → i { ^ . b v }

@ main → i {
    : *Box p # *Box ( nurl_alloc Z Box )
    = . p v 5
    ^ ( take p )
}
