// uncopyable_in_param_in_a_nested_returned_literal_lent_runs_clean: `^ @ KK { @ K { p 0 } 1 }`, `p` a `% Drop` value with no copy, read by the caller after it has used the result
// D4c (AGORA-995): a literal nested in a returned literal lends the `in` parameter it names whole, a value with no copy included; the reference checker carries the inner literal's no-copy record to the outer one, which is handed back as it is (review of github#2280).
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-995: a nested returned literal lends an uncopyable parameter
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: K { D d i n }

: KK { K k i m }

@ wrap D p → KK { ^ @ KK { @ K { p 0 } 1 } }

@ main → i {
    : D x @ D { ( string_from `a value long enough to own a heap buffer here` ) }
    : KK r ( wrap x )
    ( nurl_println ( string_data . . . r k d s ) )
    ( nurl_println ( string_data . x s ) )
    ^ 0
}
