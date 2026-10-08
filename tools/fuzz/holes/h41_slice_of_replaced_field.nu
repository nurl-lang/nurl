// H41: a Slice of a struct's Vec field is read after the field is given a new Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Box2 { ( Vec i ) buf }

@ main → i {
    : ~ Box2 o @ Box2 { ( vec_new [i] ) }
    ( vec_push [i] . o buf 7 )
    : ( Slice i ) s ( slice_from_vec [i] . o buf )
    = . o buf ( vec_new [i] )
    ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
