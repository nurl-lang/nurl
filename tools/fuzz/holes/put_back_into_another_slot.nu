// put_back_into_another_slot: an element read out of one slot (vec_at) was written back into another (vec_put_back): two slots held one String, and the one it replaced leaked.
// Closed: vec_put_back trusts its caller to name the slot the value was read from, which the compiler does not check — it is raw, `unsafe` only, as mem_put_back is.
// main's compiler: heap-use-after-free.
// map: §3 | B | rejected | h248 | vec_put_back writes element read from slot 0 into slot 1: two owners
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to own a heap buffer` ) )
    ( vec_push [String] v ( string_from `another string long enough to own one too` ) )
    : ~ String x ( vec_at [String] v 0 )
    ( vec_put_back [String] v 1 x )
    ( nurl_println ( string_data ( vec_at [String] v 1 ) ) )
    ^ 0
}
