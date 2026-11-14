// literal_moves_a_struct_holding_a_drop_value_whole: a returned struct literal took a field of a local struct (`^ @ Who { 0 . w st }`) whose type holds a `% Drop` value directly (`St { String path Conn c }`): h264's rule moved the field whole and zeroed it in `w`, and w's drop ran Conn's destructor on the zero Conn.
// Refused: zeroed, a String, a Vec or an option is empty, a `% Drop` value is not; a field whose zero value would run one is lent, and a lend of a local's field is refused out of a returned literal, as h327's is (AGORA-865).
// main's compiler: accepted; the run ended in SIGSEGV in Conn's drop.
// map: §7.6 | A2 | rejected | - | AGORA-865: a returned literal moved whole, zeroed, a struct field holding a `% Drop` value directly; the zero value's destructor ran
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

: St { String path Conn c }
: Who { i status St st }

@ who_in i n → Who {
    : Who w @ Who { n @ St { ( string_from `p` ) @ Conn { ( string_from `conn` ) } } }
    ? != . w status 0 { ^ w } {}
    ^ @ Who { 0 . w st }
}

@ main → i {
    : Who w ( who_in 0 )
    ( nurl_println ( string_data . . . w st c name ) )
    ^ 0
}
