// should_fail_inout_generic_forward.nu — a GENERIC `inout` function,
// exactly like an ordinary one, must be DEFINED before it is called.
//
// compute_generic_inout_sink records the type-independent inout index
// set when the generic template is stored (gen_generic_fn_store), and
// scan_fn_sigs records `<fname>__has_inout` in its pre-pass. A call
// compiled before the definition would not yet know to pass the
// argument by address and would miscompile silently — the call site
// rejects it with a clear diagnostic instead. Expect COMPILE FAIL.

@ main → i {
    : ~ i n 0
    ( bump_g [i] n 7 )  // `bump_g` is generic + defined below — rejected
    ^ 0
}

@ bump_g [A] inout i slot A item → v {
    = slot + slot 1
}
