// block_value_through_its_own_binding: a value handed out of a block through a binding the block declared — `: v { : t ( vec_at outer 0 ) t }` — borrowed nothing: the block's value was not modelled, and the borrow the inner `let` took ended with the block's name. Releasing `outer` left `v` dangling. (The same hid a view of an Arc's payload from the frozen-payload rule.)
// Closed: a value-position block notes what each binding it declares holds (its `let`, an assignment there, one in a block nested in it), and its value's source expression names those instead of the block's own names.
// main (before this PR): ASan heap-use-after-free.
// map: StmtT.free | A1 | rejected | h216 | block value is a block-local borrow of outer; outer freed, value read
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 5 )
    : ( Vec ( Vec i ) ) outer ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] outer seed )
    : b c == 1 1
    : ( Vec i ) v { : ( Vec i ) t ( vec_at [( Vec i )] outer 0 ) t }
    ( vec_free [( Vec i )] outer )
    ( nurl_println_int ( vec_len [i] v ) )
    ^ 0
}
