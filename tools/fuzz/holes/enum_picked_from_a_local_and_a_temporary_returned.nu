// enum_picked_from_a_local_and_a_temporary_returned: agora #477 — `: E y ( pick2 o ( mk … ) k )  ^ y` for an auto-drop enum: the picker copies its result where the temporary was owned; y owns that copy and hands it back
// Closed: a binding of a call whose result the call copied owns that copy by the call's own bit, before any borrow or view reading of the call (agora #477).
// main: LeakSanitizer reported the copy of the temporary's payload (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #477: an enum picked from a local and a temporary, returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Word String Bare }

@ mk s t → E { ^ @ E { Word ( string_from t ) } }

@ pick2 E a E b i k → E { ? == k 0 { ^ a } { ^ b } }

@ run i k → E {
    : E o ( mk `a local value long enough for the heap` )
    : E y ( pick2 o ( mk `a temporary value long enough for the heap` ) k )
    ^ y
}

@ main → i {
    : E a ( run 0 )
    : E b ( run 1 )
    ?? a { Word s → { ( nurl_println ( string_data s ) ) } Bare → {} }
    ?? b { Word s → { ( nurl_println ( string_data s ) ) } Bare → {} }
    ^ 0
}
