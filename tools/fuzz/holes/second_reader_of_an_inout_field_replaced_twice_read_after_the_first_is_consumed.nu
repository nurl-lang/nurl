// map: §2.10 | A2 | rejected | - | agora #387 / AGORA-951: two readers of an inout parameter's field, two stores, the first reader consumed, then the second read
// AGORA-951 (closed, not a hole in safe code): refused - the first store hands the old value to the first reader `a`, and `b` becomes its borrow (bck_fview_take); the second store's old value is released; `b` ends with `a`. The same shape inside an `unsafe` body through a raw pointer is outside the guarantee (MEMORY.md §3)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Rec { String name i id }

@ consume sink String s → v {}

@ twice inout Rec r → i {
    : String a . r name
    : String b . r name
    = . r name ( string_from `first replacement, long enough` )
    = . r name ( string_from `second replacement, long enough` )
    ( consume a )
    ^ ( string_len b )
}

@ main → i {
    : ~ Rec r @ Rec { ( string_from `original value, long enough` ) 1 }
    ^ ( twice r )
}
