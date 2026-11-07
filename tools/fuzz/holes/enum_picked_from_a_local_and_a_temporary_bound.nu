// enum_picked_from_a_local_and_a_temporary_bound: agora #477 — `: E y ( pick2 o ( mk … ) k )` for an auto-drop enum: a two-argument picker given a local and a temporary copies its result where the temporary was owned, but the let took y for a borrow and registered no owner
// Closed: a binding of a call whose result the call copied owns that copy by the call's own bit, before any borrow or view reading of the call (agora #477).
// main: LeakSanitizer reported the copy of the temporary's payload on the k=1 run (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #477: an enum picked from a local and a temporary, bound
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Word String Bare }

@ mk s t → E { ^ @ E { Word ( string_from t ) } }

@ pick2 E a E b i k → E { ? == k 0 { ^ a } { ^ b } }

@ run i k → i {
    : E o ( mk `a local value long enough for the heap` )
    : E y ( pick2 o ( mk `a temporary value long enough for the heap` ) k )
    : ~ i n 0
    ?? y { Word s → { = n ( string_len s ) } Bare → {} }
    ^ n
}

@ main → i {
    ( nurl_println_int ( run 0 ) )
    ( nurl_println_int ( run 1 ) )
    ^ 0
}
