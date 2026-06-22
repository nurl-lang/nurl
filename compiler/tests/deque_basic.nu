// Regression: std/deque.nu ring buffer. Exercises both-ends push/pop,
// indexed access, wraparound + growth while head != 0, and the
// owned-element free_with path (ASan). Prints a FAIL line per failed
// check; returns the failure count.

$ `stdlib/std/deque.nu`
$ `stdlib/core/string.nu`

@ expect_int i got i want s label → i {
    ? == got want { ^ 0 } {}
    ( nurl_print `  FAIL ` ) ( nurl_print label )
    ( nurl_print ` got ` ) ( nurl_print ( nurl_str_int got ) )
    ( nurl_print ` want ` ) ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
    ^ 1
}

@ expect_opt_i ? i got i want s label → i {
    : ~ i bad 1
    ?? got { T v → { ? == v want { = bad 0 } {} } F → {} }
    ? > bad 0 { ( nurl_print `  FAIL opt ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ main → i {
    : ~ i fails 0

    : ( Deque i ) d ( deque_new [i] )
    ( deque_push_back [i] d 1 )
    ( deque_push_back [i] d 2 )
    ( deque_push_back [i] d 3 )
    ( deque_push_front [i] d 0 )  // [0,1,2,3]
    = fails + fails ( expect_int ( deque_len [i] d ) 4 `len4` )
    = fails + fails ( expect_opt_i ( deque_front [i] d ) 0 `front` )
    = fails + fails ( expect_opt_i ( deque_back [i] d ) 3 `back` )
    = fails + fails ( expect_opt_i ( deque_get [i] d 2 ) 2 `get2` )
    = fails + fails ( expect_opt_i ( deque_pop_front [i] d ) 0 `pf` )
    = fails + fails ( expect_opt_i ( deque_pop_back [i] d ) 3 `pb` )  // [1,2]
    = fails + fails ( expect_int ( deque_len [i] d ) 2 `len2` )

    // Force several growths while head != 0 so the unwrap path runs.
    : ~ i i 0
    ~ < i 20 { ( deque_push_back [i] d + 100 i ) = i + i 1 }
    = fails + fails ( expect_int ( deque_len [i] d ) 22 `len22` )
    = fails + fails ( expect_opt_i ( deque_pop_front [i] d ) 1 `seq1` )
    = fails + fails ( expect_opt_i ( deque_pop_front [i] d ) 2 `seq2` )
    : ~ i k 0
    : ~ b okseq T
    ~ < k 20 {
        : i want + 100 k
        ?? ( deque_pop_front [i] d ) { T v → { ? != v want { = okseq F } {} } F → { = okseq F } }
        = k + k 1
    }
    ? ! okseq { ( nurl_print `  FAIL wrap-seq\n` ) = fails + fails 1 } {}
    = fails + fails ( expect_int ( deque_len [i] d ) 0 `drained` )
    ? ! ( deque_is_empty [i] d ) { ( nurl_print `  FAIL not empty\n` ) = fails + fails 1 } {}
    // pop on empty → None
    ?? ( deque_pop_front [i] d ) { T _ → { ( nurl_print `  FAIL empty-pop\n` ) = fails + fails 1 } F → {} }
    ( deque_free [i] d )

    // Owned String elements + free_with (ASan / leak path).
    : ( Deque String ) sd ( deque_new [String] )
    ( deque_push_back [String] sd ( string_from `a` ) )
    ( deque_push_front [String] sd ( string_from `b` ) )  // [b, a]
    = fails + fails ( expect_int ( deque_len [String] sd ) 2 `slen` )
    : ?String fo ( deque_front [String] sd )
    : s fr ?? fo { T s → ( string_data s ) F → `` }
    ? != 1 ( nurl_str_eq fr `b` ) { ( nurl_print `  FAIL sfront\n` ) = fails + fails 1 } {}
    ( deque_free_with [String] sd \ String s → v { ( string_free s ) } )

    ? == fails 0 { ( nurl_print `deque: all checks PASS\n` ) } {
        ( nurl_print `deque: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
