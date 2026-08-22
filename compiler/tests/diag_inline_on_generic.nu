// diag_inline_on_generic.nu — `inline` on a generic function (grammar v2.7).
//
// A generic is stored at parse time and monomorphised after the whole
// program is parsed, by which point the prefix has been read and cleared —
// so the instantiations would come out unmarked. nurlc says so rather than
// accept a prefix that does nothing, the same rule `simd` has.

inline @ id [A] A x → A { ^ x }

@ main → i { ^ ( id [i] 0 ) }
