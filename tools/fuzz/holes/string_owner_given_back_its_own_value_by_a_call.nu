// string_owner_given_back_its_own_value_by_a_call: agora #419 — `= o ( id o )`: the call hands back o's own value (the shape the fix must keep)
// Closed: a result that is the old value keeps it and its flag (agora #419).
// main: accepted, ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #419: `= o ( id o )`: the call hands back o's own value (the shape the fix must keep)
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ run i k → v {
    : String other ( string_from `another value long enough for the heap` )
    : ~ String o ( string_from `a value long enough for the heap here` )
    = o ( id o )
    ( nurl_println ( string_data o ) )
    ( nurl_println ( string_data other ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
