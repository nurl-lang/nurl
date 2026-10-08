// H106: a method call was judged by the trait's bare name, which has a contract and no body — an impl that keeps its argument had it dropped under it by the caller, and a temporary handed to a method leaked.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Tr [T] {
    @ f T self String x → i
}

: Keeper { ( Vec String ) kept }

% Tr Keeper { @ f Keeper k String x → i { ( vec_push [String] . k kept x ) ^ ( vec_len [String] . k kept ) } }

@ main → i {
    : Keeper k @ Keeper { ( vec_new [String] ) }
    : String a ( string_from `abcd` )
    : i r ( f k a )
    ( nurl_print_int + r ( string_len ( vec_at [String] . k kept 0 ) ) ) ( nurl_print `\n` )
    ^ 0
}
