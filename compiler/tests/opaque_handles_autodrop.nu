// opaque_handles_autodrop.nu — a module's opaque handle is released by the
// language (stdlib/core/rcbox.nu).
//
// A handle like Regex keeps its state in an rcbox: every copy — a struct
// field, a Vec element, `Regex_share` — is the same state, and the last
// owner releases it. Nothing below calls a `*_free`, and every round must
// leave the live allocation count where it found it. Before, each handle
// leaked unless freed by hand, exactly once, by exactly one of its copies.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/regex.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/bitset.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Rule { Regex re i id }

// Compiled, matched, stored twice, dropped with its owners.
@ regex_round → i {
    : ~ i hits 0
    ?? ( regex_compile `a(b+)c` ) {
        T re → {
            : ( Vec Rule ) rules ( vec_new [Rule] )
            ( vec_push [Rule] rules @ Rule { ( Regex_share re ) 1 } )
            ( vec_push [Rule] rules @ Rule { ( Regex_share re ) 2 } )
            ? ( regex_test re `xxabbbcyy` ) { = hits + hits 1 } {}
            ?? ( vec_get [Rule] rules 1 ) {
                T r → { ? ( regex_test . r re `abc` ) { = hits + hits 1 } {} }
                F → {}
            }
        }
        F e → {}
    }
    // A pattern that fails to compile leaves nothing behind either.
    ?? ( regex_compile `a(b` ) { T re → { = hits + hits 100 } F e → {} }
    ^ hits
}

: Sampler { Rng g Bitset seen }

// A generator and a bit set shared between a struct and their creator:
// both copies are the same state.
@ rng_bitset_round → i {
    : Rng g ( rng_seed 42 )
    : Bitset seen ( bitset_new 64 )
    : Sampler sm @ Sampler { ( Rng_share g ) ( Bitset_share seen ) }
    : ~ i k 0
    ~ < k 32 { ( bitset_set . sm seen ( rng_below . sm g 64 ) ) = k + k 1 }
    // The creator's copy saw every draw the struct's copy made.
    : Bitset copy ( bitset_clone seen )
    ^ ? == ( bitset_count copy ) ( bitset_count . sm seen ) ( bitset_count seen ) -1
}

@ main → i {
    : ~ i hits ( regex_round )
    : i bits ( rng_bitset_round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 { = hits + hits ( regex_round ) ( rng_bitset_round ) = k + k 1 }
    : i l1 ( live )
    ( nurl_println ( nurl_str_cat `regex hits ` ( nurl_str_int hits ) ) )
    ( nurl_println ( nurl_str_cat `distinct draws ` ( nurl_str_int bits ) ) )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
