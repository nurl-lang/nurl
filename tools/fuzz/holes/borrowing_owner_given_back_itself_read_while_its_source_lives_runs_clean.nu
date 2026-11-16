// borrowing_owner_given_back_itself_read_while_its_source_lives_runs_clean: o borrows other, `= o ( id o )`, both read while other lives
// Control: `=`'s own binding handed to its call keeps refusing nothing where nothing it borrowed ends (agora #873).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-873: o borrows other, `= o ( id o )`, both read while other lives
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( id other )
    = o ( id o )
    ( show o )
    ( show other )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
