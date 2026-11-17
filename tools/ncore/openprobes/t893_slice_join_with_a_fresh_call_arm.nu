// map: §7.6 | A2 | runs-clean | - | AGORA-893: a `?` join of slices with a call's fresh slice on one arm leaks it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ run b c → v { : [i a [i | 1 2] : [i x ? c ( mk ) a ( nurl_println_int ( ln x ) ) ( nurl_println_int ( ln ? c ( mk ) a ) ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
