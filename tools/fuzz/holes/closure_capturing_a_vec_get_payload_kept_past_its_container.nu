// closure_capturing_a_vec_get_payload_kept_past_its_container: agora #483 — a closure captures a `vec_get` payload bound in a `??` arm and outlives the container
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure capturing a vec_get payload kept past its container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string freed at the end of its block, captured as a payload` ) )
        ?? ( vec_get [String] t 0 ) {
            T y → { = f \ → i { ^ ( strlen ( string_data y ) ) } }
            F _ → {}
        }
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
