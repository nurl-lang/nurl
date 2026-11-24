// in_option_payload_lent_back_by_a_returned_match_read_after_runs_clean: the payload of an `in` option parameter handed back as the value of a `??` - returned, bound and then returned, through a forwarder, given temporaries, of a type with no copy - is lent on the run that hands it back and the result's own on the run that makes a fresh value; the caller keeps its option and reads it after it has used the result.
// D4c (AGORA-995, the owner's decision #4173): as `?? o { T x → { ^ x } … }` in the arm already was. Before it the parameter was an inferred `sink` and the caller's read was refused ("use of moved value"), and a bound join over a parameter (`: String r ? c p ( mk )  ^ r`) copied the String on the runs it lent.
// map: §7.6 | A2 | runs-clean | - | AGORA-995: an `in` option parameter's payload handed back by a match is lent, per call
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ mkv → ( Vec i ) {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ v
}

@ pay ? String o → String { ^ ?? o { T x → x F → ( mk ) } }

@ pay_bound ? String o → String {
    : String r ?? o { T x → x F → ( mk ) }
    ^ r
}

@ pick String p i k → String {
    : String r ? == k 0 p ( mk )
    ^ r
}

@ fwd ? String o → String { ^ ( pay o ) }

@ payv ? ( Vec i ) o → ( Vec i ) { ^ ?? o { T x → x F → ( mkv ) } }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : ?String n @ ?String { F }
    : String a ( pay o )
    : String b ( pay n )
    : String c ( pay_bound o )
    : String d ( pay_bound n )
    : String e ( fwd o )
    : String f ( pay @ ?String { T ( mk ) } )
    : String g ( pay_bound @ ?String { F } )
    : String s ( mk )
    : String h ( pick s 0 )
    : String j ( pick s 1 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data c ) )
    ( nurl_println ( string_data d ) )
    ( nurl_println ( string_data e ) )
    ( nurl_println ( string_data f ) )
    ( nurl_println ( string_data g ) )
    ( nurl_println ( string_data h ) )
    ( nurl_println ( string_data j ) )
    ( nurl_println ( string_data s ) )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    : ?( Vec i ) ov @ ?( Vec i ) { T ( mkv ) }
    : ( Vec i ) va ( payv ov )
    : ( Vec i ) vb ( payv @ ?( Vec i ) { F } )
    ( nurl_println ( nurl_str_int + ( vec_len [i] va ) ( vec_len [i] vb ) ) )
    ?? ov { T x → { ( nurl_println ( nurl_str_int ( vec_len [i] x ) ) ) } F → {} }
    ^ 0
}
