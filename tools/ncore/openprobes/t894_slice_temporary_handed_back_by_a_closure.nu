// map: §7.6 | A2 | runs-clean | - | AGORA-894: a slice temporary handed back by a closure leaks
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ main → i { : ( @ [i [i ) f \ [i a → [i { ^ a } : [i x ( f ( mk ) ) ( nurl_println_int . x 1 ) ^ 0 }
