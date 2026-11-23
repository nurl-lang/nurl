// option_owner_given_back_a_pick_ten_calls_deep: `= o ( id ( id … ( pick o other k ) … ) )`: the pick ten calls deep
// AGORA-966 (AGORA-946 D4a): refused at any depth - a depth cut-off at eight let the pick through (CodeRabbit on github#2226)
// map: §7.6 | A2 | rejected | - | AGORA-966 (AGORA-946 D4a): `= o ( id ( id … ( pick o other k ) … ) )`: the pick ten calls deep
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ id ? String a → ?String { ^ a }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( id ( id ( id ( id ( id ( id ( id ( id ( id ( id ( pick o other 1 ) ) ) ) ) ) ) ) ) ) )
    ( show o )
    = o ( id ( id ( id ( id ( id ( id ( id ( id ( id ( id ( pick o other 0 ) ) ) ) ) ) ) ) ) ) )
    ( show o )
    ( show other )
    ^ 0
}
