// diag_borrow_field_path.nu — a borrow taken through a field argument ends
// when that field is handed to a call that may drop what it holds, and the
// diagnostic names the field the borrow came from.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items ( Vec String ) other }

@ main → i {
    : Bag b @ Bag { ( vec_new [String] ) ( vec_new [String] ) }
    ( vec_push [String] . b items ( string_from `element` ) )
    : String e ( vec_at [String] . b items 0 )
    ( vec_clear [String] . b items )
    ( nurl_println ( string_data e ) )
    ^ 0
}
