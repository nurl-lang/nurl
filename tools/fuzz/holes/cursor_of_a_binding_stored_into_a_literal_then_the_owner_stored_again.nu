// cursor_of_a_binding_stored_into_a_literal_then_the_owner_stored_again: `: ~ cur t`, `@ H { cur 0 }`, then `@ K { t }`: two owners of one buffer
// Closed: a `: ~` copy of an owner's handle that is stored (a literal, a field, a keeping call) takes its owner with it — the generated code hands the store the owner's own value — so the owner is moved from there; and a cursor over a parameter, stored into a literal or field the function keeps to itself, is copied as the parameter is (agora #824).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #824: the owner stored again after its cursor was stored
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }
: K { ( Vec i ) v }

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : ~ ( Vec i ) cur t
    : ~ H q @ H { cur 0 }
    : K k @ K { t }
    ( nurl_println_int + ( vec_len [i] . q items ) ( vec_len [i] . k v ) )
    ^ 0
}
