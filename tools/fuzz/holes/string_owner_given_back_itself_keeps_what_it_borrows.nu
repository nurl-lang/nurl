// string_owner_given_back_itself_keeps_what_it_borrows: a String owner, `= o ( id other )` then `= o ( id o )`
// Closed: the walk reads an `=`'s own binding, handed to its call, as its old value: the new value borrows what the binding borrowed before (obs_, bck_take_plend; agora #873).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-873: a String owner, `= o ( id other )` then `= o ( id o )`
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ run i k → v {
    : ~ String other ( string_from `another value long enough for the heap` )
    : ~ String o ( string_from `a value long enough for the heap here` )
    = o ( id other )
    = o ( id o )
    = other ( string_from `a replacement value long enough for the heap` )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
