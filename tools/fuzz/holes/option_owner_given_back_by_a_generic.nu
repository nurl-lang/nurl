// option_owner_given_back_by_a_generic: `= o ( pick [?String] o other k )`, a generic callee.
// AGORA-966 (AGORA-946 D4a): refused - the form is A2's refused one in every spelling; main acec7a34 let it through on a per-call key
// map: §7.6 | A2 | rejected | - | AGORA-966 (AGORA-946 D4a): an option owner given back by a generic
$ `stdlib/core/string.nu`

@ pick [A] A a A b i k → A { ? == k 1 { ^ a } {} ^ b }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pick [? String] o other 1 )
    ( show o )
    = o ( pick [? String] o other 0 )
    ( show o )
    ^ 0
}
