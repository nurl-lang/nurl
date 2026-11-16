// option_owner_given_back_through_mutual_recursion_is_refused: `= o ( pr o other k )`, `pr` and `pr2` mutually recursive, each handing back either argument.
// Guard for agora #427: refused as the direct #412 form is — no per-run answer is right on both kinds of run.
// map: §7.6 | A2 | rejected | - | agora #427 guard: an option owner given back through mutual recursion
$ `stdlib/core/string.nu`

@ pr ? String a ? String b i k → ?String { ? == k 0 { ^ b } {} ? == k 1 { ^ a } {} ^ ( pr2 a b - k 2 ) }

@ pr2 ? String a ? String b i k → ?String { ? <= k 1 { ^ ( pr a b k ) } {} ^ a }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pr o other 1 )
    ( show o )
    = o ( pr o other 3 )
    ( show o )
    = o ( pr o other 0 )
    ( show o )
    ^ 0
}
