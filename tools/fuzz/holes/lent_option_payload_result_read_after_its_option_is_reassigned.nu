// lent_option_payload_result_read_after_its_option_is_reassigned: the result of `^ ?? o { T x → x F → ( mk ) }` read after the caller gave its option a new value - the payload the result borrowed was released
// D4c (AGORA-995): the payload of an `in` option parameter handed back by a match is lent on that run, so the result borrows the caller's option; using it after the option is gone is refused, as for `^ p`. Before it the parameter was an inferred `sink`, the option moved in, and this program was accepted.
// map: §2.5 | A2 | rejected | - | AGORA-995: the result of `^ ?? o { T x → x … }` read after the caller gave its option a new value
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ pay ? String o → String { ^ ?? o { T x → x F → ( mk ) } }

@ main → i {
    : ~ ? String o @ ?String { T ( mk ) }
    : String s ( pay o )
    = o @ ?String { F }
    ( nurl_println ( string_data s ) )
    ^ 0
}
