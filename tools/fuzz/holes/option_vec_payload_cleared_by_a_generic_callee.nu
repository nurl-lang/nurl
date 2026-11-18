// map: §2.10 | A2 | rejected | - | AGORA-428: an element view of an option's Vec payload kept while a generic `gclear [A] inout ?( Vec A )` clears it
// AGORA-428 (closed by AGORA-842 part 1): refused - the view of the payload, named past its arm, points into the option, which the growth ends (main 34edc2a1: accepted)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ gclear [A] inout ? ( Vec A ) o → v { ?? o { T q → { ( vec_clear [A] q ) } F → {} } }

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a heap string long enough to own a buffer on the heap, surely` ) )
    : ~ ? ( Vec String ) ov @ ?( Vec String ) { T xs }
    : s v ?? ov { T q → ( string_data ( vec_at [String] q 0 ) ) F → `none` }
    ( gclear [String] ov )
    ( nurl_println v )
    ^ 0
}
