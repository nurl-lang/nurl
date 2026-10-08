// H38: protobuf's ProtoReader over a Vec is read after the Vec is freed.
$ `stdlib/core/vec.nu`
$ `stdlib/ext/protobuf.nu`

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 8 ) ( vec_push [u] v # u 1 )
    ?? ( proto_reader v ) {
        T r0 → {
            : ~ ProtoReader r r0
            ( vec_free [u] v )
            ?? ( proto_read_tag r ) { T t → { ( nurl_println_int . t number ) } F e → {} }
        }
        F e → {}
    }
    ^ 0
}
