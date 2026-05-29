// should_fail_uaf_indirect.nu — indirect use-after-free check.
//
// `take` consumes its parameter `s` by calling the `_free` destructor
// on it. The borrow checker auto-infers a `sink` convention for
// `take`'s arg 0 (because the body passes the param to a destructor),
// so the caller in `main` sees `s` as moved after `( take s )`. The
// later `( string_data s )` is a use-after-move — should COMPILE FAIL.
$ `stdlib/core/string.nu`

@ take String s → v {
    ( string_free s )
}

@ main → i {
    : String s ( string_from `hello` )
    ( take s )
    ( nurl_print ( string_data s ) )  // ← use after move
    ^ 0
}
