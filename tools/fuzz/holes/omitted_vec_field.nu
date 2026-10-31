// omitted_vec_field: a struct literal that leaves a ( Vec i ) field out zero-initialises it, and a zero Vec has no control block: the first vec_push wrote through a null one.
// Closed: outside `unsafe` a field whose type has no valid zero value (a String, a Vec, a library handle, a closure, or a struct holding one) must be given (gen_agg_lit, __zero_invalid).
// ASan: SEGV in vec_push (main), reading the null control block's length.
// map: §6.2 | B | rejected | h180 | struct literal omits Vec field: zero Vec with null control block, push writes null
$ `stdlib/core/vec.nu`

: Bag { i n ( Vec i ) items }

@ main → i {
    : Bag b @ Bag { 5 }
    ( vec_push [i] . b items 3 )
    ( nurl_println_int ( vec_len [i] . b items ) )
    ^ 0
}
