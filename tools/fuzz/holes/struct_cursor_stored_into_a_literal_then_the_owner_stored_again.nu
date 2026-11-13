// struct_cursor_stored_into_a_literal_then_the_owner_stored_again: `: ~ H c h`, `@ W { c }`, then `@ W { h }`: two owners of one value
// Closed: a `: ~` copy of an owner's handle that is stored (a literal, a field, a keeping call) takes its owner with it — the generated code hands the store the owner's own value — so the owner is moved from there; and a cursor over a parameter, stored into a literal or field the function keeps to itself, is copied as the parameter is (agora #824).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #824: a struct's cursor stored, then the struct itself
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }
: W { H h }

@ main → i {
    : ~ H h @ H { ( vec_new [i] ) 0 }
    ( vec_push [i] . h items 1 )
    : ~ H c h
    : W w @ W { c }
    : W w2 @ W { h }
    ( nurl_println_int + ( vec_len [i] . . w h items ) ( vec_len [i] . . w2 h items ) )
    ^ 0
}
