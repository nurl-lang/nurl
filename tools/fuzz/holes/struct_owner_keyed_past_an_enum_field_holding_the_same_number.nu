// struct_owner_keyed_past_an_enum_field_holding_the_same_number: agora #431 — `= o ( ppick o other k )`, P { Tag t String s }, both values' Tag `Id 1`: the key is the String field, not the enum's number
// Closed: #419's identity test keys a struct by its first field that keys whatever it holds (mem_identity_key): an enum field that may hold a number, or an option, is passed over; the hand-over keeps mem_handle_key (agora #431).
// main: accepted; AddressSanitizer reported heap-use-after-free on the run that hands back the other value.
// map: §7.6 | A2 | runs-clean | - | agora #431: `= o ( ppick o other k )`, P { Tag t String s }, both values' Tag `Id 1`: the key is the String field, not the enum's number
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ show String s → v { ( nurl_println ( string_data s ) ) }

: | Tag { Id i Name String }
: P { Tag t String s }

@ ppick P a P b i k → P { ? == k 0 { ^ a } { ^ b } }

@ run i k → v {
    : P other @ P { @ Tag { Id 1 } ( string_from `another value long enough for the heap` ) }
    : ~ P o @ P { @ Tag { Id 1 } ( string_from `a value long enough for the heap here` ) }
    = o ( ppick o other k )
    ( show . o s )
    ( show . other s )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
