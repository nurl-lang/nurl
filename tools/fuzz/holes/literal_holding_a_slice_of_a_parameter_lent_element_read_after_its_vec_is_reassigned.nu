// literal_holding_a_slice_of_a_parameter_lent_element_read_after_its_vec_is_reassigned: the element `( get @ V { ( slice_from_vec [String] p ) 0 } )` hands back, read after the caller gave its Vec a new value
// Guard: the element is the Vec's, lent through the literal's slice; reading it after the Vec is replaced is refused, as for `( vec_get … )`.
// main: rejected.
// map: §2.5 | A2 | rejected | - | AGORA-995: a lend through a literal's view outlives its owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: V { ( Slice String ) t i n }

@ get V v → String { ^ ( slice_at [String] . v t 0 ) }

@ f ( Vec String ) p → String { ^ ( get @ V { ( slice_from_vec [String] p ) 0 } ) }

@ main → i {
    : ~ ( Vec String ) s ( vec_new [String] )
    ( vec_push [String] s ( string_from `a string long enough to own a heap buffer here` ) )
    : String r ( f s )
    = s ( vec_new [String] )
    ( nurl_println ( string_data r ) )
    ( nurl_println_int ( vec_len [String] s ) )
    ^ 0
}
