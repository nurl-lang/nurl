// vec_elem_handle_alias: a String read out of a Vec (copy of the handle), Vec released, copy read.
// map: StmtT.free | A1 | rejected | h24 | vec_get element borrow read after the Vec is freed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `element string on the heap, long one` ) )
    : String e ?? ( vec_get [String] vs 0 ) { T x → x F → ( string_from `` ) }
    ( vec_free [String] vs )
    ( nurl_println ( string_data e ) )
    ^ 0
}
