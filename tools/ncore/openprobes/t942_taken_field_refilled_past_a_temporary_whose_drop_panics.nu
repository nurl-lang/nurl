// t942_taken_field_refilled_past_a_temporary_whose_drop_panics: AGORA-942 (open; filed from AGORA-939) — a sink took `. h buf` of an `inout` parameter; before the refill, a value's `% Drop` panics at its scope's end, an unwind point no `unw` row marks
// AGORA-942 (open): accepted by nurlc and ncore; a `recover`ing caller gets `h` back with `buf` empty and its next push reads a null handle (tools/fuzz/holes/open/t942.md)
// map: §3.3d | A2 | rejected | - | AGORA-942: a taken inout field, then a value whose destructor panics before the refill
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

: D { i k }

% Drop D { @ drop D d → v {
        ? > . d k 2 { ( panic `in a drop` ) } {}
    } }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    // (no call between the take and the refill: `t`'s drop at the block's
    // end is the only code that runs, and it may panic)
    { : D t @ D { k } }
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
