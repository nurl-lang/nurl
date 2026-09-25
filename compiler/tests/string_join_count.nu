// string_join_count.nu — offline acceptance test for string_join and
// string_count added to stdlib/core/string.nu.
//
// Exercises join (complement of split, including the split→join round
// trip), separator placement, empty-vec / single-element edges, and
// non-overlapping occurrence counting. Determinism: no clock/socket/env.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ show_str s label String s → v {
    ( nurl_print label )
    ( nurl_print ` [` )
    ( nurl_print ( string_data s ) )
    ( nurl_print `]\n` )
}

@ show_int s label i v → v {
    ( nurl_print label )
    ( nurl_print ` ` )
    ( nurl_println_int v )
}

@ main → i {
    // join over a built vec
    : ( Vec String ) parts ( vec_new [String] )
    ( vec_push [String] parts ( string_from `a` ) )
    ( vec_push [String] parts ( string_from `b` ) )
    ( vec_push [String] parts ( string_from `c` ) )
    : String j1 ( string_join parts `, ` )
    ( show_str `join3   ` j1 )

    // empty separator
    : String j2 ( string_join parts `` )
    ( show_str `join_es ` j2 )

    // empty vec → empty string
    : ( Vec String ) empty ( vec_new [String] )
    : String j3 ( string_join empty `-` )
    ( show_str `join_em ` j3 )

    // single element → no separator
    : ( Vec String ) one ( vec_new [String] )
    ( vec_push [String] one ( string_from `solo` ) )
    : String j4 ( string_join one `, ` )
    ( show_str `join1   ` j4 )

    // split → join round trip
    : String src ( string_from `x,y,z` )
    : ( Vec String ) sp ( string_split src `,` )
    : String rt ( string_join sp `,` )
    ( show_str `roundtr ` rt )

    // count
    : String hay ( string_from `aaaa` )
    ( show_int `count_aa ` ( string_count hay `aa` ) )
    ( show_int `count_a  ` ( string_count hay `a` ) )
    ( show_int `count_z  ` ( string_count hay `z` ) )
    ( show_int `count_es ` ( string_count hay `` ) )

    : String csv ( string_from `a,b,,c,` )
    ( show_int `count_cm ` ( string_count csv `,` ) )

    ^ 0
}
