// value_block_of_a_shadowing_locals_field_handed_to_a_sink: `( eat { : ~ H h ( mkh ) . h a } )` beside an outer `h`: the tail is the block-local's field, which the block hands out.
// Closed: the tail field's root is told by its storage, not its name: the block-local `h`'s field goes to the callee, and the outer `h` keeps its own (agora #555).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// Since agora #575 the read of `. h a` after the block is refused: the block's `h` has taken the name for the rest of the scope (on main that read reached the block's `h`, whose field had gone to the callee). What the call is handed is as #555 left it.
// map: §2.12 | A2 | rejected | - | agora #555, #575: a value block of a shadowing block-local's field handed to a sink, then the name read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkh → H {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    ^ @ H { va ( vec_new [S] ) }
}

@ main → i {
    : ~ H h ( mkh )
    ( nurl_println_int ( eat { : ~ H h ( mkh ) . h a } ) )
    ( nurl_println_int # i ( vec_len [S] . h a ) )
    ^ 0
}
