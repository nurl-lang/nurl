// owner_lent_a_local_given_back_itself_through_a_generic_then_returned_runs_clean: the same through a generic identity
// Closed: an `=` that hands the binding back to itself keeps what its old value may be a lend of (mem_note_assign_lend), so `^ o` copies a lend of a local as it does without the self-handback (agora #873; found by its skeptic pass).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | runs-clean | - | AGORA-873: the same through a generic identity
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ back → ?String {
    : ~ ? String loc ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( id loc )
    = o ( gid [? String] o )
    ^ o
}

@ main → i {
    : ~ ? String r ( back )
    ( show r )
    ^ 0
}
