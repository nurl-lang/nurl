// struct_owner_keyed_past_an_option_field: agora #431 — `= o ( pick o other k )` with a struct whose first handle field is a ?String: the key is its String field
// Closed: #419's identity test keys a struct by its first field that keys whatever it holds (mem_identity_key): an enum field that may hold a number, or an option, is passed over; the hand-over keeps mem_handle_key (agora #431).
// main: accepted; AddressSanitizer reported heap-use-after-free on the run that hands back the other value.
// map: §7.6 | A2 | runs-clean | - | agora #431: `= o ( pick o other k )` with a struct whose first handle field is a ?String: the key is its String field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ show String s → v { ( nurl_println ( string_data s ) ) }

: P { ? String a String b }

@ ppick P a P b i k → P { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ run i k → v {
    : P other @ P { ( mk `another value long enough for the heap` ) ( string_from `another b value long enough for heap` ) }
    : ~ P o @ P { ( mk `a value long enough for the heap here` ) ( string_from `a b value long enough for the heap ok` ) }
    = o ( ppick o other k )
    ( show . o b )
    ( show . other b )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
