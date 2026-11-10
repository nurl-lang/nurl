// `= h ( bump h )`, bump handing back a literal built over a field of its
// parameter: the result holds h's own field on the run that lends it, so
// the assignment keeps that field and releases the rest. The old value was
// kept whole and the field leaked — a String, a Vec and a slice alike
// (agora #545).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: HS { String name i n }
: HV { ( Vec i ) items i n }
: H { [i items i n }
: G { H inner i m }

@ bump_s HS h → HS { ^ @ HS { . h name + . h n 1 } }
@ bump_v HV h → HV { ^ @ HV { . h items + . h n 1 } }
@ bump H h → H { ^ @ H { . h items + . h n 1 } }
@ bump_g G g → G { ^ @ G { . g inner + . g m 1 } }

@ main → i {
    : ~ HS hs @ HS { ( string_from `a long enough string to be on the heap, name` ) 0 }
    = hs ( bump_s hs )
    ( nurl_println ( string_data . hs name ) )
    ( nurl_println ( nurl_str_int . hs n ) )
    : ~ ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 5 )
    : ~ HV hv @ HV { w 0 }
    = hv ( bump_v hv )
    ( nurl_println ( nurl_str_int ( vec_len [i] . hv items ) ) )
    ( nurl_println ( nurl_str_int . hv n ) )
    : ~ H h @ H { [i | 1 2 3] 0 }
    : ~ i k 0
    ~ < k 3 {
        = h ( bump h )
        = k + k 1
    }
    ~ x . h items { ( nurl_println ( nurl_str_int x ) ) }
    ( nurl_println ( nurl_str_int . h n ) )
    // …over another binding: a copy, both keep their own.
    : H o @ H { [i | 7 8] 5 }
    = h ( bump o )
    ~ x . h items { ( nurl_println ( nurl_str_int x ) ) }
    ~ x . o items { ( nurl_println ( nurl_str_int x ) ) }
    : H o2 ( bump o )
    ~ x . o2 items { ( nurl_println ( nurl_str_int x ) ) }
    // …and a field one struct further in.
    : ~ G g @ G { @ H { [i | 1 2 3] 0 } 0 }
    = g ( bump_g g )
    ~ x . . g inner items { ( nurl_println ( nurl_str_int x ) ) }
    ( nurl_println ( nurl_str_int . g m ) )
    ^ 0
}
