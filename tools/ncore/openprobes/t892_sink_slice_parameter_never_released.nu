// map: §7.6 | A2 | runs-clean | - | AGORA-892: a `sink` slice parameter is released by no one
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ eat sink [i a → i { ^ . a 1 }
@ main → i { ( nurl_println_int ( eat ( mk ) ) ) ^ 0 }
