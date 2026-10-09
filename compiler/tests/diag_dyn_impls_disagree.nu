// diag_dyn_impls_disagree.nu — impls behind a `dyn` call must take each
// argument the same way. A call through a `%Tr` object cannot tell which
// impl runs: `Keeper` keeps the String it is handed (its caller hands it
// over), `Reader` only reads it — handed over to `Reader`, it would leak.
// The fix the message names: declare the parameter `sink` in the trait,
// or have every impl keep a copy. (Called on the concrete type, each impl
// is asked about itself and both compile: method_impl_summaries.nu.)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Tr [T] {
    @ f T self String x → i
}

: Keeper { ( Vec String ) kept }

: Reader { i n }

% Tr Keeper { @ f Keeper k String x → i { ( vec_push [String] . k kept x ) ^ ( vec_len [String] . k kept ) } }

% Tr Reader { @ f Reader r String x → i { ^ + . r n ( string_len x ) } }

@ main → i {
    : Reader rd @ Reader { 1 }
    : %Tr d ( dyn Tr rd )
    : String a ( string_from `abcd` )
    : i r ( f d a )
    ( nurl_print_int r ) ( nurl_print `\n` )
    ^ 0
}
