// Test: stdlib/std/set.nu — set_union / set_intersect / set_diff
$ `stdlib/std/set.nu`
$ `stdlib/std/hashmap.nu`

@ count_via_fold ( Set i ) st → i {
    : ( @ i i i ) inc \ i acc i _x → i { ^ + acc 1 }
    ^ ( set_fold [i i] st 0 inc )
}

// Build a sorted sum-of-elements signature so output is deterministic
// regardless of hash insertion order.
@ sum ( Set i ) st → i {
    : ( @ i i i ) plus \ i acc i x → i { ^ + acc x }
    ^ ( set_fold [i i] st 0 plus )
}

@ main → i {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }

    : ( Set i ) a ( set_new [i] )
    ( set_add [i] a 1 hi ei )
    ( set_add [i] a 2 hi ei )
    ( set_add [i] a 3 hi ei )
    ( set_add [i] a 4 hi ei )

    : ( Set i ) b ( set_new [i] )
    ( set_add [i] b 3 hi ei )
    ( set_add [i] b 4 hi ei )
    ( set_add [i] b 5 hi ei )
    ( set_add [i] b 6 hi ei )

    // union: 1,2,3,4,5,6 → len=6, sum=21
    : ( Set i ) u ( set_union [i] a b hi ei )
    ( nurl_print `union len=` )
    ( nurl_print ( nurl_str_int ( count_via_fold u ) ) )
    ( nurl_print ` sum=` )
    ( nurl_print ( nurl_str_int ( sum u ) ) )
    ( nurl_print `\n` )

    // intersect: 3,4 → len=2, sum=7
    : ( Set i ) ix ( set_intersect [i] a b hi ei )
    ( nurl_print `intersect len=` )
    ( nurl_print ( nurl_str_int ( count_via_fold ix ) ) )
    ( nurl_print ` sum=` )
    ( nurl_print ( nurl_str_int ( sum ix ) ) )
    ( nurl_print `\n` )

    // a \ b: 1,2 → len=2, sum=3
    : ( Set i ) d_ab ( set_diff [i] a b hi ei )
    ( nurl_print `diff_a_b len=` )
    ( nurl_print ( nurl_str_int ( count_via_fold d_ab ) ) )
    ( nurl_print ` sum=` )
    ( nurl_print ( nurl_str_int ( sum d_ab ) ) )
    ( nurl_print `\n` )

    // b \ a: 5,6 → len=2, sum=11
    : ( Set i ) d_ba ( set_diff [i] b a hi ei )
    ( nurl_print `diff_b_a len=` )
    ( nurl_print ( nurl_str_int ( count_via_fold d_ba ) ) )
    ( nurl_print ` sum=` )
    ( nurl_print ( nurl_str_int ( sum d_ba ) ) )
    ( nurl_print `\n` )

    // contains check on union
    ( nurl_print `union_has_5=` )
    ( nurl_print ? ( set_contains [i] u 5 hi ei ) `T` `F` )
    ( nurl_print ` union_has_99=` )
    ( nurl_print ? ( set_contains [i] u 99 hi ei ) `T` `F` )
    ( nurl_print `\n` )

    // empty cases: a ∩ ∅ = ∅; a ∪ ∅ = a copy
    : ( Set i ) e ( set_new [i] )
    : ( Set i ) ix_e ( set_intersect [i] a e hi ei )
    ( nurl_print `intersect_with_empty_len=` )
    ( nurl_print ( nurl_str_int ( count_via_fold ix_e ) ) )
    ( nurl_print `\n` )

    : ( Set i ) u_e ( set_union [i] a e hi ei )
    ( nurl_print `union_with_empty_sum=` )
    ( nurl_print ( nurl_str_int ( sum u_e ) ) )
    ( nurl_print `\n` )

    ( set_free [i] u )
    ( set_free [i] ix )
    ( set_free [i] d_ab )
    ( set_free [i] d_ba )
    ( set_free [i] ix_e )
    ( set_free [i] u_e )
    ( set_free [i] e )
    ( set_free [i] a )
    ( set_free [i] b )

    ( nurl_print `done\n` )
    ^ 0
}
