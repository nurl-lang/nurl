// A `raw` struct right after an import is a raw struct, not the import's
// alias — and it works as a generic type argument (a Vec, an Arc of it).
$ `stdlib/core/vec.nu`

raw : RI { i n }

$ `stdlib/std/arc.nu`

raw : RJ { i m }
: RH { ( Vec RI ) v ( Arc RJ ) a }

$ `stdlib/core/io.nu`

unsafe @ mk → RH {
    : ( Vec RI ) v ( vec_new [RI] )
    ( vec_push [RI] v @ RI { 7 } )
    ^ @ RH { v ( arc_new [RJ] @ RJ { 35 } ) }
}

@ main → i {
    : RH h ( mk )
    ( nurl_println_int + . ( vec_at [RI] . h v 0 ) n . ( arc_get [RJ] . h a ) m )
    ^ 0
}
