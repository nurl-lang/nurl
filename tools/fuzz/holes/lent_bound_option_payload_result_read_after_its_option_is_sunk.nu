// lent_bound_option_payload_result_read_after_its_option_is_sunk: the result of `: String r ?? o { T x → x F → ( mk ) }  ^ r` read after the caller handed its option to a `sink` - the payload the result borrowed was released
// D4c (AGORA-995): a binding of a match that lends only the caller's option hands it back lent, as the match handed back directly does; using the result after the option is gone is refused.
// map: §2.5 | A2 | rejected | - | AGORA-995: the result of a bound `?? o { T x → x … }` read after the caller sank its option
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ pay ? String o → String {
    : String r ?? o { T x → x F → ( mk ) }
    ^ r
}

@ eat sink ? String o → i { ^ 0 }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( pay o )
    ( eat o )
    ( nurl_println ( string_data s ) )
    ^ 0
}
