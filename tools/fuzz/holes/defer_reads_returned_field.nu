// defer_reads_returned_field: a returned literal moved a field out of a struct the function owns (`^ @ ?( Vec i ) { T . e out }`), and a `;` defer that runs after the return value is made pushed onto the emptied field: a Vec with no control block.
// Closed: under a defer the literal takes a copy of the field and the struct keeps its own (gen_agg_lit), and `^ . e out` moves only without one (gen_ret).
// ASan: SEGV in vec_push (peek, run by make's defer).
// map: §6.2 | A2 | runs-clean | h189 | defer pushes onto a struct field the returned literal already moved out
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Enc { i n ( Vec i ) out }

@ peek ( Vec i ) v → v { ( vec_push [i] v 9 ) ( nurl_println_int ( vec_len [i] v ) ) }

@ make → ?( Vec i ) {
    : Enc e @ Enc { 1 ( vec_new [i] ) }
    ( vec_push [i] . e out 5 )
    ; { ( peek . e out ) }
    ^ @ ?( Vec i ) { T . e out }
}

@ make2 → ( Vec i ) {
    : Enc e @ Enc { 1 ( vec_new [i] ) }
    ( vec_push [i] . e out 6 )
    ; { ( peek . e out ) }
    ^ . e out
}

@ main → i {
    ?? ( make ) { T v → { ( nurl_println_int ( vec_len [i] v ) ) } F → {} }
    : ( Vec i ) w ( make2 )
    ( nurl_println_int ( vec_len [i] w ) )
    ^ 0
}
