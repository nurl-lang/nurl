// option_owner_given_back_by_a_callee_below: `= o ( pickb o other k )` with `pickb` defined below the call.
// AGORA-966 (AGORA-946 D4a): refused - the form is A2's refused one in every spelling; main acec7a34 let it through on a per-call key
// map: §7.6 | A2 | rejected | - | AGORA-966 (AGORA-946 D4a): an option owner given back by a callee below
$ `stdlib/core/string.nu`

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pickb o other 1 )
    ( show o )
    = o ( pickb o other 0 )
    ( show o )
    ^ 0
}

@ pickb ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }
