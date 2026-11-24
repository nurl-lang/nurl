// in_param_lent_back_by_a_returned_literal_read_after_runs_clean: an `in` parameter handed back in a literal - bare, as a variant's payload, nested in another literal, as an option's payload, nested in one, named twice - is lent, as `^ p` is: the caller keeps its argument and reads it after it has used the result.
// D4c (AGORA-995, the owner's decision #4173): the result borrows the caller's argument; before it the literal took the argument over (`keeps`) and the caller's read was refused, or a hidden copy was made.
// map: §7.6 | A2 | runs-clean | - | AGORA-995: an `in` parameter handed back in a literal is lent in every spelling
$ `stdlib/core/string.nu`

: K { String a i n }
: KK { K k i m }
: K2 { String a String b }
: | E { V String W i }

@ bare String p → K { ^ @ K { p 0 } }

@ nested String p → KK { ^ @ KK { @ K { p 0 } 1 } }

@ variant String p → E { ^ @ E { V p } }

@ wrapped String p → ?String { ^ @ ?String { T p } }

@ wrapped_lit String p → ?K { ^ @ ?K { T @ K { p 0 } } }

@ twice String p → K2 { ^ @ K2 { p p } }

@ main → i {
    : String s ( string_from `a string long enough for the heap buffer here` )
    : K k ( bare s )
    ( nurl_println ( string_data . k a ) )
    : KK kk ( nested s )
    ( nurl_println ( string_data . . kk k a ) )
    : E e ( variant s )
    ?? e { V x → { ( nurl_println ( string_data x ) ) } W n → {} }
    : ?String o ( wrapped s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    : ?K ok ( wrapped_lit s )
    ?? ok { T x → { ( nurl_println ( string_data . x a ) ) } F → {} }
    : K2 t ( twice s )
    ( nurl_println ( string_data . t b ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
