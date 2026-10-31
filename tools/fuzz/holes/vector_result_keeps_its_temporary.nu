// vector_result_keeps_its_temporary: a call whose result is a SIMD vector (`v128` / `v256`) was taken for one that could point into a temporary argument, like a view (`( string_data ( mk ) )`): the temporary's drop was deferred to the result's consumer — and when the consumer is a binding (`: v128 x …`, `= x …`), nothing ever dropped it. A vector is lanes of numbers; it holds no address.
// Closed: a vector counts as a number to every question about what a value can point into (`__is_vec_num_ty`: the call result's scalar test in mem_arg_temps, `__ty_no_address`, `__ty_numbers_only`, `__wrap_of_numbers`), so the temporary is dropped after the call.
// v0.76.0: accepted; LeakSanitizer reported 80 bytes in 4 allocations — the control blocks and 16-byte buffers of the temporaries behind the bindings.
// map: §7.1 | A2 | runs-clean | h316 | a call returning a v128 was taken for a possible view of its temporary argument; the temporary's drop waited for a consumer, and a binding is none (leak)
$ `stdlib/core/vec.nu`

@ mk → ( Vec u ) { ^ ( vec_zeroed [u] 16 ) }

// Safe: reads the Vec through its API, hands back a vector of numbers.
@ lanes ( Vec u ) b → v128 { ^ ( nurl_v128_set64 ( vec_len [u] b ) 7 ) }

@ main → i {
    : v128 x ( lanes ( mk ) )
    : ~ v128 y ( nurl_v128_zero )
    = y ( lanes ( mk ) )
    : v128 z ( nurl_v128_xor ( lanes ( mk ) ) x )
    ( nurl_println_int # i ( nurl_v128_get64 y 0 ) )
    ( nurl_println_int # i ( nurl_v128_get64 z 1 ) )
    ^ 0
}
