// map: §7.6 | A2 | runs-clean | - | AGORA-891: a fresh slice handed to a call that hands its parameter back leaks on the fresh runs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ run b fresh → v { : [i a [i | 1 2] : [i x ( pick ( pick a fresh ) F ) ( nurl_println_int . x 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
