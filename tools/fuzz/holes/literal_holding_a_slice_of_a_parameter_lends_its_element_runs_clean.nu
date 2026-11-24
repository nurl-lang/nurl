// literal_holding_a_slice_of_a_parameter_lends_its_element_runs_clean: `^ ( get @ V { ( slice_from_vec [String] p ) 0 } )`, `get` handing back an element read through the literal's slice
// A literal argument holding nothing a drop releases lends nothing (AGORA-995's `__argtmp_inert__`), but one holding a view - a Slice, a raw string, a pointer - may lend what it views: here an element of the caller's Vec. Taken as inert, the forwarder lost its `retvia`, its caller took the element for its own, and the Vec released it again (heap-use-after-free under ASan, found by review of github#2280).
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-995: a literal holding a view is no inert argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: V { ( Slice String ) t i n }

@ get V v → String { ^ ( slice_at [String] . v t 0 ) }

@ f ( Vec String ) p → String { ^ ( get @ V { ( slice_from_vec [String] p ) 0 } ) }

@ main → i {
    : ~ ( Vec String ) s ( vec_new [String] )
    ( vec_push [String] s ( string_from `a string long enough to own a heap buffer here` ) )
    : String r ( f s )
    ( nurl_println ( string_data r ) )
    ( nurl_println_int ( vec_len [String] s ) )
    ^ 0
}
