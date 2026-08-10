// diag_call_missing_required_arg.nu — a named-argument call that skips a
// parameter which declares no default.
//
// NURL *does* have default parameter values ('i width = 10', see
// kwargs.nu) — this error fires only for a parameter that has none, from
// a function literally named __kw_default_or_die. The message used to
// assert the opposite, "NURL has no defaults and no overloading", so a
// model that read it learned to never use a feature the language has.
// Nothing exercised the message, which is how it shipped saying that;
// this test is why it cannot again.
//
// The positional route ('( box )') does not reach here — it is caught
// first by the plain arity check, which reports the DECLARED count and
// not the minimum, so a defaulted callee reads as "expected 2, got 0".
@ box s label i width = 10 → v {
    ( nurl_print label )
    ( nurl_print ( nurl_str_int width ) )
}

@ main → i {
    ( box width : 5 )
    ^ 0
}
