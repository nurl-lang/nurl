// Test: nurlfmt arm-arrow operator spacing (formatter regression lock).
//
// A match arm's `→` is NOT type context: an operator that begins the
// arm body (`?` ternary, `*` multiply, `!` not, `%` modulo, `? !=` /
// `? ==` conditions) must stay space-separated — the formatter used to
// glue it to the next token (`?flag`, `*x`, `?!=`), making an operator
// read as a type sigil. Return-type arrows (`→ ?i` in headers, closure
// `\ x → i`) still glue. This file is written in the canonical form the
// fixed formatter produces; the nurlfmt_check.sh gate locks it, and
// running it locks that the spelling means what it says.

@ tern ? i o i flag → i {
    ?? o {
        T x → ? flag x 0
        F → 0
    }
}

@ neq ? i o → i {
    ?? o {
        T x → ? != x 0 1 2
        F → 9
    }
}

@ dbl ? i o → i {
    ?? o {
        T n → * n 2
        F → 0
    }
}

@ inv ? b o → i {
    ?? o {
        T f → ? ! f 1 0
        F → 9
    }
}

@ rem ? i o → i {
    ?? o {
        T n → % n 3
        F → 9
    }
}

@ opt_ret i x → ?i {
    ? > x 0 { ^ @ ?i { T x } } {}
    ^ @ ?i { F }
}

@ main → i {
    ( nurl_println_int ( tern @ ?i { T 7 } 1 ) )
    ( nurl_println_int ( tern @ ?i { T 7 } 0 ) )
    ( nurl_println_int ( neq @ ?i { T 5 } ) )
    ( nurl_println_int ( neq @ ?i { T 0 } ) )
    ( nurl_println_int ( dbl @ ?i { T 21 } ) )
    ( nurl_println_int ( inv @ ?b { T F } ) )
    ( nurl_println_int ( rem @ ?i { T 10 } ) )
    : ( @ i i ) f \ i x → i { ^ + x 1 }
    ( nurl_println_int ( f 41 ) )
    ?? ( opt_ret 3 ) {
        T got → ( nurl_println_int got )
        F → ( nurl_println_int 0 )
    }
    ^ 0
}
