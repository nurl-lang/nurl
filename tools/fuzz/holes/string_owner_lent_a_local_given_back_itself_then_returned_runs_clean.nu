// string_owner_lent_a_local_given_back_itself_then_returned_runs_clean: a String owner
// Closed: an `=` that hands the binding back to itself keeps what its old value may be a lend of (mem_note_assign_lend), so `^ o` copies a lend of a local as it does without the self-handback (agora #873; found by its skeptic pass).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | runs-clean | - | AGORA-873: a String owner
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ back → String {
    : ~ String loc ( string_from `another value long enough for the heap` )
    : ~ String o ( string_from `a value long enough for the heap here` )
    = o ( id loc )
    = o ( id o )
    ^ o
}

@ main → i {
    : ~ String r ( back )
    ( nurl_println ( string_data r ) )
    ^ 0
}
