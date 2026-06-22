// Regression: std/ordmap.nu sorted-array ordered map. Insertion in
// scrambled order must read back sorted; get / contains / replace /
// remove / min / max behave; plus an int→String map exercising the
// free_with teardown (ASan). Returns the failure count.

$ `stdlib/std/ordmap.nu`
$ `stdlib/core/string.nu`

@ expect_opt_i ? i got i want s label → i {
    : ~ i bad 1
    ?? got { T v → { ? == v want { = bad 0 } {} } F → {} }
    ? > bad 0 { ( nurl_print `  FAIL opt ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ main → i {
    : ~ i fails 0

    : ( OrdMap i i ) m ( ordmap_new [i i] )
    ?? ( ordmap_set [i i] m 3 30 \ i a i b → i { ^ - a b } ) { T _ → { ( nurl_print `  FAIL set3 prev\n` ) = fails + fails 1 } F → {} }
    ?? ( ordmap_set [i i] m 1 10 \ i a i b → i { ^ - a b } ) { T _ → { ( nurl_print `  FAIL set1 prev\n` ) = fails + fails 1 } F → {} }
    ?? ( ordmap_set [i i] m 2 20 \ i a i b → i { ^ - a b } ) { T _ → { ( nurl_print `  FAIL set2 prev\n` ) = fails + fails 1 } F → {} }

    ? != ( ordmap_len [i i] m ) 3 { ( nurl_print `  FAIL len\n` ) = fails + fails 1 } {}
    = fails + fails ( expect_opt_i ( ordmap_get [i i] m 2 \ i a i b → i { ^ - a b } ) 20 `get2` )
    ? ! ( ordmap_contains [i i] m 2 \ i a i b → i { ^ - a b } ) { ( nurl_print `  FAIL contains2\n` ) = fails + fails 1 } {}
    ? ( ordmap_contains [i i] m 5 \ i a i b → i { ^ - a b } ) { ( nurl_print `  FAIL contains5\n` ) = fails + fails 1 } {}

    // Ordered iteration: keys must be 1,2,3 regardless of insert order.
    = fails + fails ( expect_opt_i ( ordmap_key_at [i i] m 0 ) 1 `k0` )
    = fails + fails ( expect_opt_i ( ordmap_key_at [i i] m 1 ) 2 `k1` )
    = fails + fails ( expect_opt_i ( ordmap_key_at [i i] m 2 ) 3 `k2` )
    = fails + fails ( expect_opt_i ( ordmap_min_key [i i] m ) 1 `min` )
    = fails + fails ( expect_opt_i ( ordmap_max_key [i i] m ) 3 `max` )

    // Replace returns the old value; get reflects the new one.
    = fails + fails ( expect_opt_i ( ordmap_set [i i] m 2 25 \ i a i b → i { ^ - a b } ) 20 `replace` )
    = fails + fails ( expect_opt_i ( ordmap_get [i i] m 2 \ i a i b → i { ^ - a b } ) 25 `get2b` )
    ? != ( ordmap_len [i i] m ) 3 { ( nurl_print `  FAIL len after replace\n` ) = fails + fails 1 } {}

    // Remove returns the value; the key is gone afterwards.
    = fails + fails ( expect_opt_i ( ordmap_remove [i i] m 1 \ i a i b → i { ^ - a b } ) 10 `rm1` )
    ? != ( ordmap_len [i i] m ) 2 { ( nurl_print `  FAIL len after remove\n` ) = fails + fails 1 } {}
    ? ( ordmap_contains [i i] m 1 \ i a i b → i { ^ - a b } ) { ( nurl_print `  FAIL still has 1\n` ) = fails + fails 1 } {}
    ?? ( ordmap_remove [i i] m 99 \ i a i b → i { ^ - a b } ) { T _ → { ( nurl_print `  FAIL removed absent\n` ) = fails + fails 1 } F → {} }
    ( ordmap_free [i i] m )

    // int → String values, freed via free_with (key drop is a no-op).
    : ( OrdMap i String ) sm ( ordmap_new [i String] )
    ?? ( ordmap_set [i String] sm 2 ( string_from `two` ) \ i a i b → i { ^ - a b } ) { T s → ( string_free s ) F → {} }
    ?? ( ordmap_set [i String] sm 1 ( string_from `one` ) \ i a i b → i { ^ - a b } ) { T s → ( string_free s ) F → {} }
    : ?String v1 ( ordmap_get [i String] sm 1 \ i a i b → i { ^ - a b } )
    : s v1r ?? v1 { T s → ( string_data s ) F → `` }
    ? != 1 ( nurl_str_eq v1r `one` ) { ( nurl_print `  FAIL sval\n` ) = fails + fails 1 } {}
    ( ordmap_free_with [i String] sm \ i k → v {} \ String s → v { ( string_free s ) } )

    ? == fails 0 { ( nurl_print `ordmap: all checks PASS\n` ) } {
        ( nurl_print `ordmap: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
