// uncopyable_temp_arg_leaks: a temporary that cannot be copied — a struct holding a library handle's option (`St { String path ?Database db }`, agora's AgStore) — handed straight to a call that returns another such struct (`: St c ( conn ( mk ) )`) was never dropped: no summary said the result was fresh, so the temporary waited for a later call that never came.
// Closed: the callee's summary decides, as for a String or a Vec result — the temporary is dropped after the call unless the callee hands it back.
// main's compiler: LeakSanitizer, the St's path (agora leaked one per REST call through `( ag_store_conn ( ag_store ) )`).
// map: §7.1 | A2 | runs-clean | h265 | non-copyable struct temporary passed to call returning a struct leaks
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/sqlite.nu`

: St { String path ? Database db }

@ mk → St { ^ @ St { ( string_from `/orgs/a.db` ) @ ?Database { F } } }

@ len St s → i { ^ ( string_len . s path ) }

@ conn St s → St { ^ @ St { ( string_from ( string_data . s path ) ) @ ?Database { F } } }

@ main → i {
    : St c ( conn ( mk ) )
    ( nurl_println_int ( len c ) )
    ^ 0
}
