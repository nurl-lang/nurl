// option_owner_given_back_by_a_dyn_method: `= o ( pick d o other k )`, `d` a `dyn` trait object.
// AGORA-966 (AGORA-946 D4a): refused - the form is A2's refused one in every spelling; main acec7a34 let it through on a per-call key
// map: §7.6 | A2 | rejected | - | AGORA-966 (AGORA-946 D4a): an option owner given back by a dyn method
$ `stdlib/core/string.nu`

% Picker [T] {
    @ pick T self ? String a ? String b i k → ?String
}

: P { i z }

% Picker P { @ pick P p ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : P p @ P { 1 }
    : %Picker d ( dyn Picker p )
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pick d o other 1 )
    ( show o )
    = o ( pick d o other 0 )
    ( show o )
    ^ 0
}
