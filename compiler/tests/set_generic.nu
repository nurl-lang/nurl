// Test: stdlib/std/set.nu — generic Set[T]
//
// Exercises:
//   • basic add / contains / remove / len semantics
//   • duplicate add returns F (already present)
//   • remove of absent returns F
//   • Set[s] (raw-string elements) and Set[i] (int elements)
//   • set_each iteration count
//   • cap grows on first insert (lazy alloc through HashMap)

$ `stdlib/std/set.nu`

@ main → i {
    : ( @ i s ) hs \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }

    // ── Set[s] : raw-string elements ───────────────────────────────────
    : ( Set s ) ss ( set_new [s] )
    ( nurl_print `len0=` )
    ( nurl_print ( nurl_str_int ( set_len [s] ss ) ) )
    ( nurl_print ` empty=` )
    ( nurl_print ? ( set_is_empty [s] ss ) `T` `F` )
    ( nurl_print `\n` )

    // first add: T (newly inserted)
    ( nurl_print `add_alice=` )
    ( nurl_print ? ( set_add [s] ss `alice` hs es ) `T` `F` )
    // duplicate add: F
    ( nurl_print ` add_alice2=` )
    ( nurl_print ? ( set_add [s] ss `alice` hs es ) `T` `F` )
    ( nurl_print `\n` )

    ( set_add [s] ss `bob` hs es )
    ( set_add [s] ss `carol` hs es )

    ( nurl_print `len3=` )
    ( nurl_print ( nurl_str_int ( set_len [s] ss ) ) )
    ( nurl_print ` cap=` )
    ( nurl_print ( nurl_str_int ( set_cap [s] ss ) ) )
    ( nurl_print `\n` )

    // contains
    ( nurl_print `has_alice=` )
    ( nurl_print ? ( set_contains [s] ss `alice` hs es ) `T` `F` )
    ( nurl_print ` has_dave=` )
    ( nurl_print ? ( set_contains [s] ss `dave` hs es ) `T` `F` )
    ( nurl_print `\n` )

    // remove present then absent
    ( nurl_print `rm_bob=` )
    ( nurl_print ? ( set_remove [s] ss `bob` hs es ) `T` `F` )
    ( nurl_print ` rm_bob2=` )
    ( nurl_print ? ( set_remove [s] ss `bob` hs es ) `T` `F` )
    ( nurl_print `\n` )

    ( nurl_print `len_after_rm=` )
    ( nurl_print ( nurl_str_int ( set_len [s] ss ) ) )
    ( nurl_print `\n` )

    // fold — count elements via accumulator (closure capture is by value
    // so a counter mutated inside an each-closure won't propagate).
    : ( @ i i s ) inc \ i acc s _x → i { ^ + acc 1 }
    : i count ( set_fold [s i] ss 0 inc )
    ( nurl_print `fold_count=` )
    ( nurl_print ( nurl_str_int count ) )
    ( nurl_print `\n` )

    ( set_free [s] ss )

    // ── Set[i] : int elements + grow ───────────────────────────────────
    : ( Set i ) si ( set_new [i] )
    : ~ i k 0
    ~ < k 12 {
        ( set_add [i] si k hi ei )
        = k + k 1
    }
    ( nurl_print `set_i_len=` )
    ( nurl_print ( nurl_str_int ( set_len [i] si ) ) )
    ( nurl_print ` cap=` )
    ( nurl_print ( nurl_str_int ( set_cap [i] si ) ) )
    ( nurl_print `\n` )

    ( nurl_print `has_5=` )
    ( nurl_print ? ( set_contains [i] si 5 hi ei ) `T` `F` )
    ( nurl_print ` has_99=` )
    ( nurl_print ? ( set_contains [i] si 99 hi ei ) `T` `F` )
    ( nurl_print `\n` )

    ( set_free [i] si )

    ( nurl_print `done\n` )
    ^ 0
}
