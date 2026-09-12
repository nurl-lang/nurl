// diag_default_arg_type.nu — a default value whose type is not the
// parameter's.
//
// A default is spliced into the argument list of every call that omits it,
// so it is an argument and owes the same agreement. The POSITIONAL fill
// path ran no check at all: `@ show f x = 1 → v` called `( show )` emitted
// `call void @show(i64 1)` against a `double` parameter, the callee read
// xmm0, and the program printed 0 — the declared default, silently gone.
//
// The explicit-argument path has enforced this for years, and the
// named-argument path since the kwargs reorder was brought under the same
// battery. One helper now answers for all three spellings.
@ show f x = 1 → v {
    ( nurl_print `x = ` )
    ( nurl_print ( nurl_str_float x ) )
    ( nurl_print `\n` )
}

@ main → i {
    ( show )
    ^ 0
}
