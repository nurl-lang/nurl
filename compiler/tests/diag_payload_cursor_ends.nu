// diag_payload_cursor_ends.nu — a `??` arm's payload over an option
// binding is a cursor over that option's value (agora #170). Handing the
// option on, storing it, or letting a callee or a closure give it a new
// value ends the payload; handing the payload on consumes the option.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ take_opt sink ? String o → v {}

@ take_res sink ! i String r → v {}

@ opt_clear inout ? String o → v { = o @ ?String { F } }

@ run ( @ v ) f → v { ( f ) }

@ option_handed_on → v {
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( take_opt o )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
}

@ option_stored_then_freed → v {
    : ~ ( Vec ? String ) v ( vec_new [? String] )
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( vec_push [? String] v o )
            ( vec_free [? String] v )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
}

@ replaced_by_a_callee → v {
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( opt_clear o )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
}

@ replaced_by_a_closure → v {
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( run \ → v { ( opt_clear o ) } )
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
}

@ error_payload_handed_on → v {
    : ~ ! i String r @ !i String { F ( mk ) }
    ?? r {
        T n → {}
        F e → {
            ( take_res r )
            ( nurl_println ( string_data e ) )
        }
    }
}

@ payload_freed_then_option_handed_on → v {
    : ~ ? String o @ ?String { T ( mk ) }
    ?? o {
        T x → {
            ( string_free x )
            ( take_opt o )
        }
        F → {}
    }
}

@ main → i { ^ 0 }
