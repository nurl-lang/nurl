// taken_field_the_destructor_reads_through_a_block_wrapped_receiver: AGORA-929 (CodeRabbit on github#2110) — the `% Drop` hands its receiver to a helper wrapped in a block, `( inspect { c } )`, which reads `buf`, and a sink takes `. h buf`
// map: §2.14 | A2 | rejected | - | AGORA-929: a destructor reading a field through a block-wrapped receiver handed to a helper
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf i n }

@ inspect Holder c → v { ( nurl_println_int ( vec_len [u] . c buf ) ) }

% Drop Holder { @ drop Holder c → v { ( inspect { c } ) } }

@ eat sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : Holder h @ Holder { ( vec_new [u] ) 1 }
    : i k ( eat . h buf )
    ^ 0
}
