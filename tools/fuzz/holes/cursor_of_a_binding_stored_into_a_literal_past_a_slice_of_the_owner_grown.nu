// cursor_of_a_binding_stored_into_a_literal_past_a_slice_of_the_owner_grown: `: ~ cur t`, `@ H { cur 0 }`, a slice of t, then `( vec_reserve . q items 4096 )`
// Closed: a `: ~` copy of an owner's handle that is stored (a literal, a field, a keeping call) takes its owner with it — the generated code hands the store the owner's own value — so the owner is moved from there; and a cursor over a parameter, stored into a literal or field the function keeps to itself, is copied as the parameter is (agora #824). (agora #761 item 1.)
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #824: a slice of the owner past its cursor's field grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Vec i ) items i n }

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : ~ ( Vec i ) cur t
    : ~ H q @ H { cur 0 }
    : ( Slice i ) sl ( slice_from_vec [i] t )
    ( vec_reserve [i] . q items 4096 )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
