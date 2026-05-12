// Test: stdlib/core/pair.nu — Pair[A B] basics + ownership rules.

$ `stdlib/core/pair.nu`
$ `stdlib/core/string.nu`

@ main → i {
  // ── Trivial Pair[i i] ──
  : ( Pair i i ) p1 ( pair_new [i i] 3 4 )
  ( nurl_print `pair_ii=` )
  ( nurl_print ( nurl_str_int ( pair_first [i i] p1 ) ) )
  ( nurl_print `,` )
  ( nurl_print ( nurl_str_int ( pair_second [i i] p1 ) ) )
  ( nurl_print `\n` )

  // ── Pair[s i] (borrowed string + int) — trivial, no drop ──
  : ( Pair s i ) p2 ( pair_new [s i] `key` 42 )
  ( nurl_print `pair_si=` )
  ( nurl_print ( pair_first [s i] p2 ) )
  ( nurl_print `,` )
  ( nurl_print ( nurl_str_int ( pair_second [s i] p2 ) ) )
  ( nurl_print `\n` )

  // ── pair_eq with stock eq_int + eq_int ──
  : ( Pair i i ) p3 ( pair_new [i i] 3 4 )
  : ( Pair i i ) p4 ( pair_new [i i] 3 5 )
  : (@ b i i) eq_ii \ i a i b → b { ^ == a b }
  ( nurl_print `eq_p1_p3=` )
  ( nurl_print ? ( pair_eq [i i] p1 p3 eq_ii eq_ii ) `T` `F` )
  ( nurl_print `\n` )
  ( nurl_print `eq_p1_p4=` )
  ( nurl_print ? ( pair_eq [i i] p1 p4 eq_ii eq_ii ) `T` `F` )
  ( nurl_print `\n` )

  // ── Pair[String i] — owned first, drop via pair_free_a ──
  : String s1 ( string_from `hello` )
  : ( Pair String i ) p5 ( pair_new [String i] s1 7 )
  ( nurl_print `owned_first=` )
  ( nurl_print ( string_data ( pair_first [String i] p5 ) ) )
  ( nurl_print `,` )
  ( nurl_print ( nurl_str_int ( pair_second [String i] p5 ) ) )
  ( nurl_print `\n` )
  : (@ v String) drop_str \ String x → v { ( string_free x ) }
  ( pair_free_a [String i] p5 drop_str )

  // ── Pair[String String] — both owned, pair_free_with ──
  : String k ( string_from `name` )
  : String v ( string_from `nurl` )
  : ( Pair String String ) p6 ( pair_new [String String] k v )
  ( nurl_print `both_owned=` )
  ( nurl_print ( string_data ( pair_first [String String] p6 ) ) )
  ( nurl_print `=` )
  ( nurl_print ( string_data ( pair_second [String String] p6 ) ) )
  ( nurl_print `\n` )
  ( pair_free_with [String String] p6 drop_str drop_str )

  ( nurl_print `done\n` )
  ^ 0
}
