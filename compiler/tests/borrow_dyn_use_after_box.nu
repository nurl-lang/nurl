// borrow_dyn_use_after_box.nu — `( dyn Trait d )` moves an owned `d`
// into the box (dyn_box_owns_value): reading `d` afterwards reads what
// the box now owns and frees, so it is a use after move.

$ `stdlib/core/string.nu`

% Speaker [T] {
    @ speak T self i volume → i
}

: Dog { String name i pitch }

% Speaker Dog { @ speak Dog d i volume → i { ^ + ( string_len . d name ) volume } }

@ main → i {
    : Dog d @ Dog { ( string_from `rex` ) 1 }
    : %Speaker s ( dyn Speaker d )
    ( nurl_print ( string_data . d name ) )
    ^ ( speak s 1 )
}
