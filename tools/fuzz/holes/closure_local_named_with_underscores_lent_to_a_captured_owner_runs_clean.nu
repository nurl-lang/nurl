// closure_local_named_with_underscores_lent_to_a_captured_owner_runs_clean: a closure local named `__other`, lent to a captured owner: copied like any other local
// Closed: a capture by pointer given a lend of what dies with the closure is given a copy it owns; a type with no copy is refused only where an argument that dies is lent (gen_assign, resolve_cap_nc_lends; agora #872, CodeRabbit's review of github#1914).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a closure local named `__other`, lent to a captured owner: copied like any other local
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String __other ( mk `a closure local value long enough for heap` )
        = o ( id __other )
    }
    ( f )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
