// struct_picked_from_a_local_and_a_temporary_bound: agora #477 — `: H y ( pick2 o @ H { … } k )`: a two-argument picker given a local struct and a temporary literal copies its result where the temporary was owned, and y must own that copy
// Closed: a binding of a call whose result the call copied owns that copy by the call's own bit, before any borrow or view reading of the call (agora #477).
// main: LeakSanitizer reported the copy of the temporary's String on the k=1 run (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #477: a struct picked from a local and a temporary, bound
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String s i n }

@ pick2 H a H b i k → H { ? == k 0 { ^ a } { ^ b } }

@ run i k → i {
    : H o @ H { ( string_from `a local value long enough for the heap` ) 1 }
    : H y ( pick2 o @ H { ( string_from `a temporary value long enough for the heap` ) 2 } k )
    ^ + ( string_len . y s ) . y n
}

@ main → i {
    ( nurl_println_int ( run 0 ) )
    ( nurl_println_int ( run 1 ) )
    ^ 0
}
