// closure_field_into_literal_leaks_struct: a returned literal that took a closure field of a struct this function owns (`^ @ ?( @ i i ) { T . a cb }`) counted the struct as the value being returned and skipped its drop, so every other field it held leaked. The closure's type has blanks in it, and the record of the field read (`__last_field_read__`) splits on blanks: the field-move rule never saw a closure.
// Closed: the field moves out as a handle field does — emptied in the struct, which is dropped with what else it holds (gen_agg_lit reads the literal's own field type for a closure).
// main (before this PR): LeakSanitizer, the struct's Vec fields.
// map: §7.1 | A2 | runs-clean | h193 | returning closure field skips struct drop: other fields leak
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { ( Vec u ) out String name ( @ i i ) cb }

@ g → ?( @ i i ) {
    : E a @ E { ( vec_new [u] ) ( string_from `kept` ) \ i x → i { ^ + x 1 } }
    ( vec_push [u] . a out 1 )
    ^ @ ?( @ i i ) { T . a cb }
}

@ main → i {
    ?? ( g ) { T f → { ( nurl_println_int ( f 4 ) ) } F → {} }
    ^ 0
}
