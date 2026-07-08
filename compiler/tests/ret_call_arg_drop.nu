// Test: `^ ( f … x … )` must still drop x (feat/registry-pkg).
//
// gen_ret derived the "escaping binding" from `__last_ident_name__`,
// which for a direct-call return holds the call's LAST ARGUMENT — not
// the returned value. Passing an auto-dropped binding (owned string /
// `% Drop` value / owned-field struct) as an argument in tail position
// therefore cancelled its scheduled drop, leaking it on every such
// return: the callee never takes ownership of its arguments. Found by
// LSan on the registry package's `^ ( __reg_run st )`-shaped helpers
// (one leaked sqlite Statement box per query).
//
// The fix keys the skip on ret_arg_alias: a non-call return keeps the
// old behaviour (the value may BE the binding), and a call return only
// skips when the callee is summarised ret-borrow (dropping the source
// would dangle the returned alias — conservative: worst case leak,
// never UAF). The void fall-off path gets the same treatment: nothing
// escapes a `→ v` return, so a stale last-ident must never cancel a
// Drop-value's drop there.
//
// Frees are observable under ASan/LSan (run_san_tests.sh); this golden
// locks compile + run + output.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { i n }

% Drop Res {
    @ drop Res r → v {
        ( nurl_print `drop:res\n` )
    }
}

// Reads a Drop value passed by value; returns something else entirely.
@ probe Res r → i {
    ^ + . r n 1
}

// Reads an owned string arg; returns a FRESH string.
@ describe s t → s {
    ^ ( nurl_str_cat `got:` t )
}

// Shape 1 (the registry leak): `% Drop` binding passed as the tail
// call's argument — the binding's drop must still fire on this path.
@ tail_call_drop → i {
    : Res r @ Res { 41 }
    ^ ( probe r )
}

// Shape 2: owned string passed to a fresh-string-returning call in tail
// position — the argument's buffer must still be freed.
@ tail_call_str → s {
    : s owned ( nurl_str_cat `x` `y` )
    ^ ( describe owned )
}

// Shape 3: void fall-off whose LAST statement mentions a Drop binding —
// the stale last-ident must not cancel the drop at the implicit return.
@ void_falloff → v {
    : Res r @ Res { 7 }
    : i _n ( probe r )
}

// Control: bare `^ binding` still transfers ownership out (no drop in
// the callee; the caller's print proves the value survived).
@ ret_bare → s {
    : s owned ( nurl_str_cat `keep:` `alive` )
    ^ owned
}

@ main → i {
    : i a ( tail_call_drop )  // expect drop:res BEFORE the print below
    ( nurl_print `probe=` )
    ( nurl_print ( nurl_str_int a ) )
    ( nurl_print `\n` )
    // Both callees are summarised __ret_owned=str, so these bindings
    // auto-drop at scope exit — no manual frees.
    : s d ( tail_call_str )
    ( nurl_print d )
    ( nurl_print `\n` )
    ( void_falloff )
    : s k ( ret_bare )
    ( nurl_print k )
    ( nurl_print `\n` )
    ^ 0
}
