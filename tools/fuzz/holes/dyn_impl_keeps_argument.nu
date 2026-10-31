// dyn_impl_keeps_argument: a call through a trait object asked the trait's bare name what the impl does with its arguments — an impl that keeps its argument had it dropped under it by the caller.
// map: §2.12 | A2 | runs-clean | h110 | impl keeps String arg, called via trait object; caller drops it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Tr [T] {
    @ f T self String x → i
}

: Keeper { ( Vec String ) kept }

% Tr Keeper { @ f Keeper k String x → i { ( vec_push [String] . k kept x ) ^ ( vec_len [String] . k kept ) } }

@ main → i {
    : Keeper k @ Keeper { ( vec_new [String] ) }
    : %Tr d ( dyn Tr k )
    : String a ( string_from `abcd` )
    : i r ( f d a )
    ( nurl_print_int r ) ( nurl_print `\n` )
    ^ 0
}
