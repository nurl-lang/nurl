// option_owner_given_back_a_nested_pick_through_a_second_argument: `= o ( second o ( pick o other k ) )`: `second` lends its second argument, a call that may lend `o` or `other`
// AGORA-966 (AGORA-946 D4a): refused - the call may hand back the owner's own value or another one, which A2 refuses in every spelling; a nested call's lend was not followed (CodeRabbit on github#2226)
// map: §7.6 | A2 | rejected | - | AGORA-966 (AGORA-946 D4a): `= o ( second o ( pick o other k ) )`: `second` lends its second argument, a call that may lend `o` or `other`
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ second ? String a ? String b → ?String { ^ b }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( second o ( pick o other 1 ) )
    ( show o )
    = o ( second o ( pick o other 0 ) )
    ( show o )
    ^ 0
}
