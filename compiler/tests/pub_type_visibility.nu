// pub_type_visibility.nu — positive smoke test for grammar v2.0+ type
// + const visibility. The helper file marks PubPoint / PubColor /
// PUB_CONST as `pub`. Using them across the file boundary must
// compile + run cleanly.

$ `compiler/tests/should_fail_pub_type_helper.nu`

// Exercises three pub forms across files:
//   * `pub :` struct      — used at decl + struct-literal site
//   * `pub : |` enum      — constructed (variant access)
//   * `pub : i` const     — loaded as a global integer
//
// All three should compile + run cleanly. The variant-as-int cast
// is sidestepped (that's a separate enum-cast cleanup, not in scope
// for visibility); we just construct the enum and discard it,
// proving the variant name was resolvable.
@ main → i {
    : PubPoint p @ PubPoint { 3 4 }
    : PubColor c # PubColor Green
    ( nurl_print `x=` ) ( nurl_print ( nurl_str_int . p x ) ) ( nurl_print `\n` )
    ( nurl_print `y=` ) ( nurl_print ( nurl_str_int . p y ) ) ( nurl_print `\n` )
    ?? c {
        Red → ( nurl_print `color=Red\n` )
        Green → ( nurl_print `color=Green\n` )
        Blue → ( nurl_print `color=Blue\n` )
    }
    ( nurl_print `const=` ) ( nurl_print ( nurl_str_int PUB_CONST ) ) ( nurl_print `\n` )
    ^ 0
}
