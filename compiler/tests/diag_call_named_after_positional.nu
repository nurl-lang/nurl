// diag_call_named_after_positional.nu — a named argument followed by a
// positional one. Once `name: value` appears, argument position stops
// meaning anything, so the compiler refuses rather than guess which
// parameter the trailing value was for. Baselines the diagnostic TEXT:
// the rule ("name them all from that point, or none of them") is the
// half a model needs, and should_fail_* would not hold it.
@ add i x i y → i { ^ + x y }

@ main → i {
    : i r ( add x : 1 2 )
    ^ r
}
