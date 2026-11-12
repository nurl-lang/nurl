// loop_element_name_reused_by_a_payload_binding_in_the_loop_runs_clean: agora #735 — `~ x vs { : ?( Vec String ) o ( mko ) ?? o { T x → ( vec_clear x ) } }`: the arm's `x` is the fresh option's payload, not the loop element
// Control: a binding that reuses the loop element's name has sources of its own (__econt_of: the loop's note is older than the binding).
// main 4dfee821: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #735: `~ x vs { : ?( Vec String ) o ( mko ) ?? o { T x → ( vec_clear x ) } }`: the arm's `x` is the fresh option's payload, not the loop element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mko → ?( Vec String ) {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `t` ) )
    ^ @ ?( Vec String ) { T t }
}

@ ch ( Vec ( Vec String ) ) vs → v {
    ~ x vs {
        : ?( Vec String ) o ( mko )
        ?? o { T x → { ( vec_clear [String] x ) } F _ → {} }
    }
}

@ main → i {
    : ( Vec String ) a ( vec_new [String] )
    ( vec_push [String] a ( string_from `an element string long enough for a heap buffer` ) )
    : ( Vec ( Vec String ) ) vs ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vs a )
    : String e ( vec_at [String] ( vec_at [( Vec String )] vs 0 ) 0 )
    ( ch vs )
    ( nurl_println ( string_data e ) )
    ^ 0
}
