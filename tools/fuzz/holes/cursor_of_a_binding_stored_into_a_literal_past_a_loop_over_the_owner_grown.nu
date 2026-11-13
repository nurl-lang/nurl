// cursor_of_a_binding_stored_into_a_literal_past_a_loop_over_the_owner_grown: `: ~ cur t`, `@ H { cur 0 }`, then a `~` loop over t growing `. q items`
// Closed: a `: ~` copy of an owner's handle that is stored (a literal, a field, a keeping call) takes its owner with it — the generated code hands the store the owner's own value — so the owner is moved from there; and a cursor over a parameter, stored into a literal or field the function keeps to itself, is copied as the parameter is (agora #824). (agora #761 item 1.)
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #824: a loop over the owner while its cursor's field is grown
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    ( vec_push [i] t 2 )
    : ~ ( Vec i ) cur t
    : ~ H q @ H { cur 0 }
    : ~ i s 0
    ~ x t {
        ( vec_reserve [i] . q items 4096 )
        = s + s x
    }
    ( nurl_println_int s )
    ^ 0
}
