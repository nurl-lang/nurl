// dyn_call_temporary: a temporary handed to a method through a trait object leaked — the bare name's return type was unknown, so the temporary waited for a consumer that never came.
// map: §7.1 | A2 | runs-clean | h112 | temporary passed to method via trait object leaked
$ `stdlib/core/string.nu`

% Tr [T] {
    @ f T self String x → i
}

: Lens { i k }

% Tr Lens { @ f Lens l String x → i { ^ + . l k ( string_len x ) } }

@ main → i {
    : Lens l @ Lens { 1 }
    : %Tr d ( dyn Tr l )
    ( nurl_print_int ( f d ( string_from `abcd` ) ) ) ( nurl_print `\n` )
    ^ 0
}
