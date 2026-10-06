// return_raw_view_of_local.nu — a raw view of a value the function drops
// on the way out (`^ ( string_data x )`, `^ ( view_of x )`) comes back as
// the caller's own copy of the bytes, and x is dropped as usual.
//
// `^ ( string_data x )` kept x alive (a leak per call); `^ ( view_of x )`,
// the same view through a helper, dropped x under the returned pointer (a
// use-after-free). A view of a parameter stays a view of the caller's own
// argument.
$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ view_of String s → s { ^ ( string_data s ) }

@ f1 → s { : String x ( string_from `abc` ) ^ ( string_data x ) }

@ f2 → s { : String x ( string_from `abcd` ) ^ ( view_of x ) }

@ f3 String p → s { ^ ( view_of p ) }

unsafe

@ main → i {
    : String keep ( string_from `zz` )
    : i a0 - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i r 0
    : ~ i k 0
    ~ < k 10 { : s a ( f1 ) : s b ( f2 ) : s c ( f3 keep ) = r + r + + ( nurl_str_len a ) ( nurl_str_len b ) ( nurl_str_len c ) = k + k 1 }
    : i a1 - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_print_int r ) ( nurl_print ` leaked ` ) ( nurl_print_int - a1 a0 ) ( nurl_print `\n` )
    ^ 0
}
