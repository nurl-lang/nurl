// should_fail_inout_forward.nu — an `inout` function must be DEFINED
// before it is called. The inout-parameter
// set is recorded as each function is compiled; a call compiled
// before the definition would not know to pass the argument by
// address and would miscompile silently. scan_fn_sigs records
// `<fname>__has_inout`, which lets the call site reject this case
// with a clear diagnostic instead. Expect COMPILE FAIL.

: Counter { i n  i max }

@ main → i {
    : ~ Counter c @ Counter { 0 10 }
    ( bump c )            // `bump` is defined below — rejected here
    ^ 0
}

@ bump inout Counter c → v {
    = . c n + . c n 1
}
