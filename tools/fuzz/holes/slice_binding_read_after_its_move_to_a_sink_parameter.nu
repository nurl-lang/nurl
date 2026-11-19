// map: §7.6 | A2 | rejected | - | agora #892: `: [i t ( mk )  ( eat t )  . t 1`: a read of the slice after it moved to the sink
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ eat sink [i a → i { ^ . a 1 }
@ main → i {
    : [i t ( mk )
    ( nurl_println_int ( eat t ) )
    ( nurl_println_int . t 1 )
    ^ 0
}
