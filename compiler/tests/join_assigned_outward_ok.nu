// join_assigned_outward_ok.nu — a `?` / `??` whose value is assigned to a
// binding of an outer block (agora #179). What its arms bound in the
// inner block dies first:
// - a binding of its own moves out;
// - a view or a field of one is copied;
// - a cursor over an inner option takes the option's value along.
// A value of the outer block is lent as before. Runs clean under the
// sanitizers.

$ `stdlib/core/string.nu`

: P { String s i n }

: | G {
    V P
    Nil
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        : String x ( mk )
        : P p @ P { ( mk ) k }
        : String v . p s
        : ?String o @ ?String { T ( mk ) }
        : G g @ G { V @ P { ( mk ) k } }
        = t ? > k 0 x ( mk )
        = acc + acc ( string_len t )
        = t ? > k 1 . p s ( mk )
        = acc + acc ( string_len t )
        = t ? > k 2 v ( mk )
        = acc + acc ( string_len t )
        = t ?? o { T s → s F → ( mk ) }
        = acc + acc ( string_len t )
        = t ?? g { V q → . q s Nil → ( mk ) }
        = acc + acc ( string_len t )
        = t ? > k 3 ? > k 4 ( mk ) . p s ( mk )
        = acc + acc ( string_len t )
        = k + k 1
    }
    : P outer @ P { ( mk ) 1 }
    {
        = t ? > acc 0 . outer s ( mk )
    }
    ( nurl_println_int acc )
    ( nurl_println_int + ( string_len t ) ( string_len . outer s ) )
    ^ 0
}
