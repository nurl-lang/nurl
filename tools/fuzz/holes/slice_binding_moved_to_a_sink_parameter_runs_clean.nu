// map: §7.6 | A2 | runs-clean | - | agora #892: `: [i t ( mk )  ( eat t )`: the binding moves to the sink, which releases it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ eat sink [i a → i { ^ . a 1 }
@ main → i {
    : [i t ( mk )
    ( nurl_println_int ( eat t ) )
    ^ 0
}
