// binding_assigned_the_result_of_a_call_on_itself_leaks_the_lent_field: agora #545 — `= h ( bump h )`, bump handing back a literal built over a field of its parameter: the result holds h's own field on the run that lends it, and the assignment kept the old value whole — the field was then owned by nobody (a leak), or released with both values (a double free).
// Closed: the assignment keeps the field the result lends back and releases the rest of the old value; over another binding (`= h ( bump o )`) the lent field is copied and both keep their own.
// main (before this PR): AddressSanitizer, attempting double-free.
// map: §7.6 | A2 | runs-clean | - | agora #545: `= h ( bump h )` with bump lending back a field of its parameter leaked that field or freed it twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: HS { String name i n }
: HV { ( Vec i ) items i n }
: H { [i items i n }

@ bump_s HS h → HS { ^ @ HS { . h name + . h n 1 } }
@ bump_v HV h → HV { ^ @ HV { . h items + . h n 1 } }
@ bump H h → H { ^ @ H { . h items + . h n 1 } }

@ main → i {
    : ~ HS hs @ HS { ( string_from `a long enough string to be on the heap, name` ) 0 }
    = hs ( bump_s hs )
    ( nurl_println ( string_data . hs name ) )
    : ~ ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 5 )
    : ~ HV hv @ HV { w 0 }
    = hv ( bump_v hv )
    ( nurl_println ( nurl_str_int ( vec_len [i] . hv items ) ) )
    : ~ H h @ H { [i | 1 2 3] 0 }
    : ~ i k 0
    ~ < k 3 {
        = h ( bump h )
        = k + k 1
    }
    ~ x . h items { ( nurl_println ( nurl_str_int x ) ) }
    : H o @ H { [i | 7 8] 5 }
    = h ( bump o )
    ~ x . h items { ( nurl_println ( nurl_str_int x ) ) }
    ~ x . o items { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
