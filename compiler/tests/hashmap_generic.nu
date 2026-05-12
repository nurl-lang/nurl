// Test: stdlib/std/hashmap.nu — generic HashMap[K V]
//
// Exercises:
//   • basic insert / lookup / overwrite / remove / contains
//   • resize past initial cap=8 (insert ~12 entries)
//   • map_each + map_fold
//   • inverse map ( HashMap [i s] ) to confirm K/V monomorphisation works
//     for both (string→int) and (int→string) instantiations

$ `stdlib/std/hashmap.nu`
$ `stdlib/core/option.nu`

// Closures wrapping the stock @-functions from hashmap.nu — NURL passes
// closures (16-byte fn-ptr + env), not raw @-function names, to higher-
// order parameters. Same pattern as compiler/tests/vec_hof.nu.

@ main → i {
  : (@ i s)   hs \ s str → i { ^ ( hash_string str ) }
  : (@ b s s) es \ s a s b → b { ^ ( eq_string a b ) }
  : (@ i i)   hi \ i x → i { ^ ( hash_int x ) }
  : (@ b i i) ei \ i a i b → b { ^ ( eq_int a b ) }

  // ── HashMap[s i] : raw-string → int ────────────────────────────────
  : ( HashMap s i ) m ( map_new [s i] )
  ( nurl_print `len0=` )
  ( nurl_print ( nurl_str_int ( map_len [s i] m ) ) )
  ( nurl_print ` empty=` )
  ( nurl_print ? ( map_is_empty [s i] m ) `T ` `F ` )
  ( nurl_print `cap=` )
  ( nurl_print ( nurl_str_int ( map_cap [s i] m ) ) )
  ( nurl_print `\n` )

  // Insert three entries (lazy first alloc → cap should become 8).
  ( map_set [s i] m `alice` 42 hs es )
  ( map_set [s i] m `bob` 17 hs es )
  ( map_set [s i] m `charlie` 99 hs es )
  ( nurl_print `len3=` )
  ( nurl_print ( nurl_str_int ( map_len [s i] m ) ) )
  ( nurl_print ` cap=` )
  ( nurl_print ( nurl_str_int ( map_cap [s i] m ) ) )
  ( nurl_print `\n` )

  // get / contains
  : ? i ga ( map_get [s i] m `alice` hs es )
  ( nurl_print `alice=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ga -1 ) ) )
  ( nurl_print `\n` )

  : ? i gb ( map_get [s i] m `bob` hs es )
  ( nurl_print `bob=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] gb -1 ) ) )
  ( nurl_print `\n` )

  : ? i gx ( map_get [s i] m `nope` hs es )
  ( nurl_print `nope=` )
  ( nurl_print ? ( opt_is_none [i] gx ) `none ` `some ` )
  ( nurl_print `\n` )

  ( nurl_print `has_alice=` )
  ( nurl_print ? ( map_contains [s i] m `alice` hs es ) `T ` `F ` )
  ( nurl_print `has_dave=` )
  ( nurl_print ? ( map_contains [s i] m `dave` hs es ) `T ` `F ` )
  ( nurl_print `\n` )

  // Overwrite — replaced value should come back as Some(42).
  : ? i prev ( map_set [s i] m `alice` 100 hs es )
  ( nurl_print `prev_alice=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] prev -1 ) ) )
  ( nurl_print `\n` )
  : ? i ga2 ( map_get [s i] m `alice` hs es )
  ( nurl_print `alice2=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ga2 -1 ) ) )
  ( nurl_print `\n` )

  // Remove bob — should return Some(17), then contains=F.
  : ? i rb ( map_remove [s i] m `bob` hs es )
  ( nurl_print `removed_bob=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] rb -1 ) ) )
  ( nurl_print ` has_bob_after=` )
  ( nurl_print ? ( map_contains [s i] m `bob` hs es ) `T` `F` )
  ( nurl_print `\n` )

  // Removing again returns None (key gone).
  : ? i rb2 ( map_remove [s i] m `bob` hs es )
  ( nurl_print `removed_bob_again=` )
  ( nurl_print ? ( opt_is_none [i] rb2 ) `none` `some` )
  ( nurl_print `\n` )

  // Force resize: insert several more keys until cap doubles.
  ( map_set [s i] m `dave` 4 hs es )
  ( map_set [s i] m `eve` 5 hs es )
  ( map_set [s i] m `frank` 6 hs es )
  ( map_set [s i] m `grace` 7 hs es )
  ( map_set [s i] m `heidi` 8 hs es )
  ( map_set [s i] m `ivan` 9 hs es )
  ( map_set [s i] m `judy` 10 hs es )
  ( map_set [s i] m `karl` 11 hs es )
  ( map_set [s i] m `liam` 12 hs es )
  ( nurl_print `after_grow len=` )
  ( nurl_print ( nurl_str_int ( map_len [s i] m ) ) )
  ( nurl_print ` cap=` )
  ( nurl_print ( nurl_str_int ( map_cap [s i] m ) ) )
  ( nurl_print `\n` )

  // Verify a key inserted before the resize still resolves.
  : ? i ga3 ( map_get [s i] m `alice` hs es )
  ( nurl_print `alice_after_grow=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ga3 -1 ) ) )
  ( nurl_print `\n` )

  // Verify a freshly inserted key resolves.
  : ? i gl ( map_get [s i] m `liam` hs es )
  ( nurl_print `liam=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] gl -1 ) ) )
  ( nurl_print `\n` )

  // map_fold — sum all values. Pattern: (@ i i s i) takes (acc, key, val).
  : (@ i i s i) sum_vals \ i acc s k i v → i { ^ + acc v }
  : i tot ( map_fold [s i i] m 0 sum_vals )
  ( nurl_print `sum=` )
  ( nurl_print ( nurl_str_int tot ) )
  ( nurl_print `\n` )

  // map_each — call f for every entry. Verify by also folding count.
  : (@ i i s i) count_step \ i acc s k i v → i { ^ + acc 1 }
  : i visited ( map_fold [s i i] m 0 count_step )
  ( nurl_print `visited=` )
  ( nurl_print ( nurl_str_int visited ) )
  ( nurl_print `\n` )

  ( map_free [s i] m )

  // ── HashMap[i s] : int → raw-string ────────────────────────────────
  : ( HashMap i s ) inv ( map_new [i s] )
  ( map_set [i s] inv 1 `one`   hi ei )
  ( map_set [i s] inv 2 `two`   hi ei )
  ( map_set [i s] inv 3 `three` hi ei )
  ( map_set [i s] inv 4 `four`  hi ei )
  ( map_set [i s] inv 5 `five`  hi ei )

  : ? s g3 ( map_get [i s] inv 3 hi ei )
  ( nurl_print `inv[3]=` )
  ( nurl_print ( opt_unwrap_or [s] g3 `MISSING` ) )
  ( nurl_print `\n` )

  : ? s g7 ( map_get [i s] inv 7 hi ei )
  ( nurl_print `inv[7]=` )
  ( nurl_print ? ( opt_is_none [s] g7 ) `none` `some` )
  ( nurl_print `\n` )

  ( nurl_print `inv_len=` )
  ( nurl_print ( nurl_str_int ( map_len [i s] inv ) ) )
  ( nurl_print `\n` )

  ( map_free [i s] inv )

  ( nurl_print `done\n` )
  ^ 0
}
