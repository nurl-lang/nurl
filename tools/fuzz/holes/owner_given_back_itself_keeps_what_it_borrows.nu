// owner_given_back_itself_keeps_what_it_borrows: `= o ( id other )` then `= o ( id o )`: o still borrows other, which is then replaced and o read
// Closed: the walk reads an `=`'s own binding, handed to its call, as its old value: the new value borrows what the binding borrowed before (obs_, bck_take_plend; agora #873).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-873: `= o ( id other )` then `= o ( id o )`: o still borrows other, which is then replaced and o read
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( id other )
    = o ( id o )
    = other ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
