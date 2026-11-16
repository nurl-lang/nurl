// owner_picked_back_from_itself_keeps_what_it_borrows: `= o ( pick o o k )`, a pick of the binding and itself
// Closed: the walk reads an `=`'s own binding, handed to its call, as its old value: the new value borrows what the binding borrowed before (obs_, bck_take_plend; agora #873).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-873: `= o ( pick o o k )`, a pick of the binding and itself
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ fwd ? String a → ?String { ^ ( id a ) }

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ? String third ( mk `a third value long enough for the heap` )
    = o ( id other )
    = o ( pick o o k )
    = other ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
