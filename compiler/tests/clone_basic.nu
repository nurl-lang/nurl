// Test: stdlib Clone story — string_clone / vec_clone / vec_clone_with /
// vec_filter_with / map_clone / map_clone_with.
//
// Each case clones a value, mutates the SOURCE, and confirms the clone
// is unaffected (independent storage). Owned-element cases free both the
// source and the clone to prove there is no double-free (ASan-clean).
//
// Closures wrap the stock @-functions — NURL passes closure values
// (16-byte fn-ptr + env), not raw @-function names, to higher-order
// parameters.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/core/option.nu`

@ main → i {
    // ── string_clone : independent deep copy ───────────────────────
    : String s1 ( string_new )
    ( string_push_str s1 `hello` )
    : String s2 ( string_clone s1 )
    ( string_push_str s1 ` world` )  // mutate the source only
    ( nurl_print `str: src=` )
    ( nurl_print ( string_data s1 ) )
    ( nurl_print ` clone=` )
    ( nurl_print ( string_data s2 ) )
    ( nurl_print `\n` )
    ( string_free s1 )
    ( string_free s2 )

    // ── vec_clone : trivial Vec[i] shallow copy ────────────────────
    : ( Vec i ) vi ( vec_new [i] )
    ( vec_push [i] vi 10 )
    ( vec_push [i] vi 20 )
    ( vec_push [i] vi 30 )
    : ( Vec i ) vic ( vec_clone [i] vi )
    : b _e0 ( vec_set [i] vi 0 999 )  // mutate the source only
    ( nurl_print `vec_i: src0=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( vec_get [i] vi 0 ) -1 ) ) )
    ( nurl_print ` clone0=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( vec_get [i] vic 0 ) -1 ) ) )
    ( nurl_print ` clonelen=` )
    ( nurl_print ( nurl_str_int ( vec_len [i] vic ) ) )
    ( nurl_print `\n` )
    ( vec_free [i] vi )
    ( vec_free [i] vic )

    // ── vec_clone_with : owned Vec[String] ─────────────────────────
    : ( @ String String ) sclone \ String s → String { ^ ( string_clone s ) }
    : ( @ v String ) sdrop \ String s → v { ( string_free s ) }
    : ( @ v String ) sshow \ String s → v {
        ( nurl_print ( string_data s ) )
        ( nurl_print ` ` )
    }
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `alpha` ) )
    ( vec_push [String] vs ( string_from `beta` ) )
    ( vec_push [String] vs ( string_from `gamma` ) )
    : ( Vec String ) vsc ( vec_clone_with [String] vs sclone )
    ( vec_push [String] vs ( string_from `delta` ) )  // grow source only
    ( nurl_print `vec_str: srclen=` )
    ( nurl_print ( nurl_str_int ( vec_len [String] vs ) ) )
    ( nurl_print ` clonelen=` )
    ( nurl_print ( nurl_str_int ( vec_len [String] vsc ) ) )
    ( nurl_print ` clone=[ ` )
    ( vec_each [String] vsc sshow )
    ( nurl_print `]\n` )

    // ── vec_filter_with : owned-safe filter over Vec[String] ───────
    : ( @ b String ) keep_long \ String s → b { ^ > ( string_len s ) 4 }
    : ( Vec String ) vsf ( vec_filter_with [String] vs keep_long sclone )
    ( nurl_print `filter: kept=` )
    ( nurl_print ( nurl_str_int ( vec_len [String] vsf ) ) )
    ( nurl_print ` [ ` )
    ( vec_each [String] vsf sshow )
    ( nurl_print `]\n` )
    ( vec_free_with [String] vsf sdrop )
    ( vec_free_with [String] vsc sdrop )
    ( vec_free_with [String] vs sdrop )

    // ── map_clone : trivial HashMap[s i] shallow copy ──────────────
    : ( @ i s ) hs \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }
    : ( HashMap s i ) mi ( map_new [s i] )
    ( map_set [s i] mi `one` 1 hs es )
    ( map_set [s i] mi `two` 2 hs es )
    ( map_set [s i] mi `three` 3 hs es )
    : ( HashMap s i ) mic ( map_clone [s i] mi )
    ( map_set [s i] mi `four` 4 hs es )  // add to the source only
    ( nurl_print `map_i: srclen=` )
    ( nurl_print ( nurl_str_int ( map_len [s i] mi ) ) )
    ( nurl_print ` clonelen=` )
    ( nurl_print ( nurl_str_int ( map_len [s i] mic ) ) )
    ( nurl_print ` clone[two]=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( map_get [s i] mic `two` hs es ) -1 ) ) )
    ( nurl_print ` clone[four]=` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( map_get [s i] mic `four` hs es ) -1 ) ) )
    ( nurl_print `\n` )
    ( map_free [s i] mi )
    ( map_free [s i] mic )

    // ── map_clone_with : owned HashMap[s String] deep copy ─────────
    : ( @ s s ) kid \ s k → s { ^ k }
    : ( HashMap s String ) ms ( map_new [s String] )
    ( map_set [s String] ms `a` ( string_from `apple` ) hs es )
    ( map_set [s String] ms `b` ( string_from `banana` ) hs es )
    : ( HashMap s String ) msc ( map_clone_with [s String] ms kid sclone )
    ( nurl_print `map_str: srclen=` )
    ( nurl_print ( nurl_str_int ( map_len [s String] ms ) ) )
    ( nurl_print ` clonelen=` )
    ( nurl_print ( nurl_str_int ( map_len [s String] msc ) ) )
    ( nurl_print `\n` )
    // Free every owned value in both maps, then the maps themselves.
    // A double-free here would trip ASan.
    ( map_each [s String] ms \ s k String val → v { ( string_free val ) } )
    ( map_each [s String] msc \ s k String val → v { ( string_free val ) } )
    ( map_free [s String] ms )
    ( map_free [s String] msc )

    ( nurl_print `done\n` )
    ^ 0
}
