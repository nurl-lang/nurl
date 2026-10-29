// payload_cursor_ok.nu — a `??` arm's payload over an option binding
// (agora #170): read before the option is handed on, taken over by a `=`
// that gives the option a new value, freed in the arm, and matched again
// in a loop after each new value. Each runs clean.

$ `stdlib/core/string.nu`

@ take_opt sink ? String o → v {}

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `first` ) }
    ?? o {
        T x → {
            = o @ ?String { T ( string_from `second` ) }
            ( nurl_println ( string_data x ) )
        }
        F → {}
    }
    ?? o {
        T x → {
            ( nurl_println ( string_data x ) )
            ( take_opt o )
        }
        F → {}
    }
    : ~ ? String p @ ?String { T ( string_from `third` ) }
    ?? p {
        T y → { ( string_free y ) }
        F → {}
    }
    : ~ ? String q @ ?String { T ( string_from `loop` ) }
    : ~ i k 0
    ~ < k 2 {
        ?? q {
            T z → {
                ( nurl_println ( string_data z ) )
                = q @ ?String { T ( string_from `again` ) }
            }
            F → {}
        }
        = k + k 1
    }
    ^ 0
}
