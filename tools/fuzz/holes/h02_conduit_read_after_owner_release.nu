// H2: a handle stored into an owner, the owner released, the handle read by name.
$ `stdlib/core/vec.nu`

: Box1 { ( Vec i ) items }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : Box1 b @ Box1 { xs }
    ( vec_free [i] . b items )
    ( nurl_println_int ( vec_len [i] xs ) )
    ^ 0
}
