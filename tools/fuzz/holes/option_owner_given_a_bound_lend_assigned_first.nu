// option_owner_given_a_bound_lend_assigned_first: agora #425 — as option_owner_given_a_bound_lend_of_itself_or_another, the assignment before any read of t
// Closed: the hand-over of o's old value keys an option borrower by its payload, as it keys the owner (mem_udrop_hand_over); it compared against nothing — IR clang rejected (agora #425).
// main: did not compile (`icmp eq i8* , %rN`).
// map: §7.6 | A2 | runs-clean | - | agora #425: as option_owner_given_a_bound_lend_of_itself_or_another, the assignment before any read of t
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ first ? String a ? String b → ?String { ^ a }

@ run i k → v {
    : ?String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ?String t ( first o other )
    = o t
    ( show o )
    ( show other )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
