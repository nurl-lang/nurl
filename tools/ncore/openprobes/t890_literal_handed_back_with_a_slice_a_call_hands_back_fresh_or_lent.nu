// map: §7.6 | A2 | runs-clean | - | AGORA-890: a literal handed back whose slice field is a call that answers per run leaks the slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ mkbag [i a b fresh → Bag { ^ @ Bag { ( pick a fresh ) 2 } }
@ run b fresh → v { : [i a [i | 1 2] : Bag g ( mkbag a fresh ) ( nurl_println_int . . g s 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
