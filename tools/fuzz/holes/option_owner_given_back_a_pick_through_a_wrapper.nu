// option_owner_given_back_a_pick_through_a_wrapper: `= o ( id ( pick o other k ) )`: a one-argument wrapper hands back what `pick` may lend
// AGORA-966 (AGORA-946 D4a): refused - the call may hand back the owner's own value or another one, which A2 refuses in every spelling; a nested call's lend was not followed (CodeRabbit on github#2226)
// map: §7.6 | A2 | rejected | - | AGORA-966 (AGORA-946 D4a): `= o ( id ( pick o other k ) )`: a one-argument wrapper hands back what `pick` may lend
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ id ? String a → ?String { ^ a }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( id ( pick o other 1 ) )
    ( show o )
    = o ( id ( pick o other 0 ) )
    ( show o )
    ^ 0
}
