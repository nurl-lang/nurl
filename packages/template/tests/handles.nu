// tests/handles.nu — a TplSet is a handle: copies share one set, and the set
// is released by its last owner (tset_free is only an early release);
// tset_load_dir reports a missing directory and skips unreadable entries.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `src/template.nu`
$ `src/loader.nu`

: Holder { TplSet set i n }

@ report s name b good → i {
    ? good {
        ( nurl_print `PASS ` ) ( nurl_print name ) ( nurl_print `\n` )
        ^ 0
    } {
        ( nurl_print `FAIL ` ) ( nurl_print name ) ( nurl_print `\n` )
        ^ 1
    }
}

@ renders TplSet t s name s want → b {
    ?? ( tset_render t name ( json_null ) ) {
        T got → { ^ == ( nurl_str_eq ( string_data got ) want ) 1 }
        F _ → { ^ F }
    }
}

@ main → i {
    : ~ i fails 0
    : TplSet t ( tset_new )
    ( tset_add t `hi` `hello` )
    // a copy shares the set: what is added through one is seen by the other
    : Holder h @ Holder { ( mem_dup t ) 1 }
    ( tset_add . h set `bye` `goodbye` )
    = fails + fails ( report `copy shares the set` ( renders t `bye` `goodbye` ) )
    : ( Vec TplSet ) sets ( vec_new [TplSet] )
    ( vec_push [TplSet] sets ( mem_dup t ) )
    ?? ( vec_get [TplSet] sets 0 ) {
        T s → { = fails + fails ( report `copy in a Vec renders` ( renders s `hi` `hello` ) ) }
        F → { = fails + 1 fails }
    }
    // an early release of one owner leaves the others working
    ( tset_free ( mem_dup t ) )
    = fails + fails ( report `early release of a copy` ( renders . h set `hi` `hello` ) )
    // the loader: a missing directory, and an entry that cannot be read
    : TplSet t2 ( tset_new )
    = fails + fails ( report `missing directory` < ( tset_load_dir t2 `/nonexistent/nurl-tpl` `.tpl` ) 1 )
    : String dir ( string_from `/tmp/nurl-tpl-handles` )
    : i32 _m1 ( mkdir ( string_data dir ) # i32 493 )
    : i32 _m2 ( mkdir `/tmp/nurl-tpl-handles/sub.tpl` # i32 493 )
    : !v IoErr _w ( write_file `/tmp/nurl-tpl-handles/ok.tpl` `fine` )
    : i loaded ( tset_load_dir t2 ( string_data dir ) `.tpl` )
    = fails + fails ( report `unreadable entry skipped` == loaded 1 )
    = fails + fails ( report `loaded template renders` ( renders t2 `ok` `fine` ) )
    ? == fails 0 { ( nurl_print `ALL PASS\n` ) } {}
    ^ fails
}
