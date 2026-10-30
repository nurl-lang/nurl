// nested_lending_call_borrowed_nothing: a binding of a call whose lent argument was itself a lending call — `( vec_at ( vec_at top 0 ) 0 )`, `( vec_get ( arc_get a ) 0 )`, a `??` over one — borrowed only what the outer call was handed directly. That was a temporary, so the binding borrowed nothing, and releasing `top` left it dangling.
// Closed: a `let` / assignment / `match` of such a call carries the call's source expression, and the binding (or payload) borrows every source a lent argument reaches.
// main (before this PR): ASan heap-use-after-free.
// map: derive | A1 | rejected | h214 | borrow of vec_at of vec_at depends on root top; top freed, inner read
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 5 )
    : ( Vec ( Vec i ) ) mid ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] mid seed )
    : ( Vec ( Vec ( Vec i ) ) ) top ( vec_new [( Vec ( Vec i ) )] )
    ( vec_push [( Vec ( Vec i ) )] top ( vec_clone [( Vec i )] mid ) )
    : ( Vec i ) inner ( vec_at [( Vec i )] ( vec_at [( Vec ( Vec i ) )] top 0 ) 0 )
    ( vec_free [( Vec ( Vec i ) )] top )
    ( nurl_println_int ( vec_len [i] inner ) )
    ^ 0
}
