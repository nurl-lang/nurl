// literal_takes_uncopyable_field: a returned struct literal took a field of a struct this function owns (`^ @ Who { 0 . w st rs }`) without moving it when the field's type owns something but is no copyable handle — a struct holding a library handle's option (`St { String path ?Database db }`, agora's AgStore). Neither zeroed in `w` nor copied, it was freed with `w` at return while the result still held it.
// Closed: such a field moves whole — zeroed at the source while the struct owns it — as a String or Vec field does.
// main's compiler: ASan heap-use-after-free reading `. w st path` after `who_in` returned (agora's GET /m/me).
// map: §7.6 | A2 | runs-clean | h264 | returned struct literal copies non-copyable field; freed with source struct
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/sqlite.nu`

: St { String path ? Database db }
: Who { i status St st St rs }

@ blank → St { ^ @ St { ( string_new ) @ ?Database { F } } }

@ who → Who {
    ^ @ Who { 0 @ St { ( string_from `/orgs/a.db` ) @ ?Database { F } } ( blank ) }
}

@ who_in → Who {
    : Who w ( who )
    ? != . w status 0 { ^ w } {}
    : St rs @ St { ( string_from `/repos/r.db` ) @ ?Database { F } }
    ^ @ Who { 0 . w st rs }
}

@ main → i {
    : Who w ( who_in )
    ( nurl_println_int ( string_len . . w st path ) )
    ^ 0
}
