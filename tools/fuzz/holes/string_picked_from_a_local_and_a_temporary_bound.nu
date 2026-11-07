// string_picked_from_a_local_and_a_temporary_bound: agora #477 — `: String y ( pick2 o ( string_from … ) k )`: a two-argument picker given a local and a temporary copies its result where the temporary was owned, and y must own that copy
// Closed: a binding of a call whose result the call copied owns that copy by the call's own bit, before any borrow or view reading of the call (agora #477).
// main: LeakSanitizer reported the copy of the temporary on the k=1 run (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #477: a String picked from a local and a temporary, bound
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick2 String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ run i k → i {
    : String o ( string_from `a local value long enough for the heap` )
    : String y ( pick2 o ( string_from `a temporary value long enough for the heap` ) k )
    ^ ( string_len y )
}

@ main → i {
    ( nurl_println_int ( run 0 ) )
    ( nurl_println_int ( run 1 ) )
    ^ 0
}
