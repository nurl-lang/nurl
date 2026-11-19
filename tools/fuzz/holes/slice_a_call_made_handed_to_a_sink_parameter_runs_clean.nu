// map: §7.6 | A2 | runs-clean | - | agora #892: `( eat ( mk ) )`, `eat sink [i a`: the callee releases the slice the call made
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ eat sink [i a → i { ^ . a 1 }
@ main → i { ( nurl_println_int ( eat ( mk ) ) ) ^ 0 }
