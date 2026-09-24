// closure_env_ownership.nu — every place a closure can be kept owns its
// env and drops it (docs/MEMORY.md §7.5). Nothing below frees by hand.
//
// Each section is one way a closure outlives the expression that made
// it: returned from a function (on a fresh path, a borrowed path, a
// mixed-path function, a forward-declared one), rebound, bound in a
// loop, passed straight into a call, stored into a struct (literal,
// constructor, field store, reassignment), captured by another closure,
// chosen by a `?` / `??` join, held in a slice, thrown away. Run under
// LeakSanitizer it is leak-clean; under ASan it is free of double-free
// and use-after-free — a wrongly dropped env would be read by the
// invocation that follows it, and its captured value would be garbage.

$ `stdlib/core/string.nu`

: Holder { ( @ i ) f }

@ mk i seed → ( @ i ) { ^ \ → i { ^ + seed 1 } }

@ apply ( @ i ) f → i { ^ ( f ) }

@ apply2 ( @ i ) f → i { ^ ( apply f ) }

// Returns its borrowed parameter: the caller gets its own copy.
@ id ( @ i ) f → ( @ i ) { ^ f }

// Fresh on one path, borrowed on the other.
@ either b fresh ( @ i ) f i k → ( @ i ) {
    ? fresh { ^ \ → i { ^ + k 100 } } {}
    ^ f
}

@ stash i seed → Holder { ^ @ Holder { \ → i { ^ + seed 2 } } }

// Stores its borrowed parameter into the struct it returns.
@ wrap ( @ i ) f → Holder { ^ @ Holder { f } }

@ main → i {
    : i b 5

    // Returned, rebound, and in a loop.
    : ~ ( @ i ) r ( mk 10 )
    ( nurl_println_int ( r ) )  // 11
    = r ( mk 20 )
    ( nurl_println_int ( r ) )  // 21
    : ~ i k 0
    ~ < k 3 {
        : ( @ i ) q ( mk k )
        ( nurl_println_int ( q ) )  // 1 2 3
        = k + k 1
    }

    // A borrowed return, a mixed-path return, a forward function.
    : ( @ i ) f \ → i { ^ + b 1 }
    : ( @ i ) g ( id f )
    ( nurl_println_int ( g ) )  // 6
    : ( @ i ) e1 ( either T f 1 )
    : ( @ i ) e2 ( either F f 2 )
    ( nurl_println_int + ( e1 ) ( e2 ) )  // 107
    : ( @ i ) fw ( later 3 )
    ( nurl_println_int ( fw ) )  // 1003

    // Temporaries passed straight into calls, one hop and two.
    ( nurl_println_int ( apply ( mk 30 ) ) )  // 31
    ( nurl_println_int ( apply2 \ → i { ^ + b 2 } ) )  // 7

    // Structs: constructor, literal of a borrowed binding, field store,
    // reassignment from a constructor.
    : ~ Holder h ( stash 40 )
    : ( @ i ) h0 . h f
    ( nurl_println_int ( h0 ) )  // 42
    = . h f \ → i { ^ + b 3 }
    : ( @ i ) h1 . h f
    ( nurl_println_int ( h1 ) )  // 8
    = h ( stash 50 )
    : ( @ i ) h2 . h f
    ( nurl_println_int ( h2 ) )  // 52
    : Holder w ( wrap f )
    : ( @ i ) w0 . w f
    ( nurl_println_int ( w0 ) )  // 6

    // Captured by another closure; returned and captured.
    : ( @ i ) outer \ → i { ^ + ( f ) ( g ) }
    ( nurl_println_int ( outer ) )  // 12
    : ( @ i ) m ( mk 60 )
    : ( @ i ) mm \ → i { ^ * ( m ) 2 }
    ( nurl_println_int ( mm ) )  // 122

    // Joins: a call beside a literal, a borrowed binding beside a call.
    : ( @ i ) j1 ? > b 0 ( mk 70 ) \ → i { ^ 0 }
    ( nurl_println_int ( j1 ) )  // 71
    : ?i opt @ ?i { T 80 }
    : ( @ i ) j2 ?? opt { T x → ( mk x ) F → f }
    ( nurl_println_int ( j2 ) )  // 81

    // A slice of closures.
    : [( @ i ) sl [( @ i ) | ( mk 90 ) f ( mk 91 )]
    ( nurl_println_int . sl length )  // 3

    // Thrown away.
    ( mk 99 )
    ( stash 99 )
    ^ 0
}

@ later i k → ( @ i ) { ^ \ → i { ^ + k 1000 } }
