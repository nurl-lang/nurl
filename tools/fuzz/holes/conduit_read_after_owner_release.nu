// conduit_read_after_owner_release: a handle stored into an owner, the owner released, the handle read by name.
// map: §2.12 | A2 | rejected | h02 | Vec stored in struct field, field freed, original name read
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
