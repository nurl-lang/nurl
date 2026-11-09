// try_over_a_join_binding_lent_out_of_a_local: `: !i Res q ? c ( getr pb ) ( getr lb )  : i v \ q`, with lb a local dropped field by field (B3 holds a Res of its own) and getr handing back `. b r`: on the path that took lb's field, `\ q` handed the caller lb's error, which lb released on the way out. `^ q` was refused, `\ q` not.
// Closed: the try's failure path asks what `^ q` asks of a binding lent out of a local of this frame (mem_payload_local_lend) and refuses a value that cannot be copied (agora #546).
// main 0f8390d3: accepted; AddressSanitizer: heap-use-after-free reading the error in main.
// map: §7.6 | A2 | rejected | - | agora #546: a try over a join binding lent out of a local handed the caller what the local released
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mkr i k → Res {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v k )
    ^ @ Res { v }
}

@ bad i k → !i Res { ^ @ !i Res { F ( mkr k ) } }

: B3 { ! i Res r Res x }

@ getr B3 b → !i Res { ^ . b r }

@ f b c B3 pb i k → !i Res {
    : B3 lb @ B3 { ( bad k ) ( mkr 1 ) }
    : !i Res q ? c ( getr pb ) ( getr lb )
    : i v \ q
    ^ @ !i Res { T v }
}

@ main → i {
    : B3 b @ B3 { ( bad 5 ) ( mkr 2 ) }
    ?? ( f F b 3 ) { T x → ( nurl_println_int x ) F e → ( nurl_println_int ( vec_at [i] . e buf 0 ) ) }
    ^ 0
}
