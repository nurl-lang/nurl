// owner_given_back_itself_read_then_its_source_replaced: o read after `= o ( id o )`, then other replaced and o read again
// Closed: the walk reads an `=`'s own binding, handed to its call, as its old value: the new value borrows what the binding borrowed before (obs_, bck_take_plend; agora #873).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-873: o read after `= o ( id o )`, then other replaced and o read again
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
    = other ( mk `x replacement value long enough for the heap` )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
