// generic_string_literal.nu — regression: string literals inside a
// GENERIC function body must survive monomorphisation.
//
// A generic template is stored as reconstructed source text and re-lexed
// at each instantiation. Before the fix, `nurl_lex_val` stripped a string
// literal's backticks (and decoded its escapes), so `` `hit` `` came back
// as the bare identifier `hit` — "use of undefined identifier 'hit'" at
// the instantiation. __tok_src_text now re-wraps + re-escapes TT_STR.

$ `stdlib/core/string.nu`

// String literal in a generic body + an escape sequence to exercise the
// re-escaping path (\n \t \\).
@ classify [A] A x s label → s {
    ^ ? != 0 ( nurl_str_eq label `hit` ) { `match` } { `no\tmatch\n` }
}

@ main → i {
    ( nurl_print ( classify [i] 1 `hit` ) )
    ( nurl_print `\n` )
    ( nurl_print ( classify [i] 1 `nope` ) )
    // Distinct instantiation (A = s) shares the same template source.
    ( nurl_print ( classify [s] `q` `hit` ) )
    ( nurl_print `\n` )
    ^ 0
}
