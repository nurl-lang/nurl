// vec_owner_given_back_itself_keeps_what_it_borrows: a Vec owner, `= o ( vid other )` then `= o ( vid o )`, other replaced, an element of o read
// Closed: the walk reads an `=`'s own binding, handed to its call, as its old value: the new value borrows what the binding borrowed before (obs_, bck_take_plend; agora #873).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-873: a Vec owner, `= o ( vid other )` then `= o ( vid o )`, other replaced, an element of o read
$ `stdlib/core/vec.nu`

@ vid ( Vec i ) a → ( Vec i ) { ^ a }

@ run i k → v {
    : ~ ( Vec i ) other ( vec_new [i] )
    ( vec_push [i] other 7 )
    : ~ ( Vec i ) o ( vec_new [i] )
    ( vec_push [i] o 8 )
    = o ( vid other )
    = o ( vid o )
    = other ( vec_new [i] )
    ( nurl_println ( nurl_str_int ( vec_at [i] o 0 ) ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
