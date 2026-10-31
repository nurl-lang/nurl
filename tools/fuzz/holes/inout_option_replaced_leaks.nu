// inout_option_replaced_leaks: assigning a whole option over an `inout ?T` parameter (`= o @ ?String { … }`), or over an owned `?T` module global, stored the new option over the caller's without dropping it: the old string leaked on every store.
// Closed: an assignment that replaces an option or a result through an `inout` place (a parameter, an owned global) drops what the place held, as it does a String or a Vec there (gen_assign).
// main (before this PR): LeakSanitizer, one string per replaced option.
// map: §7.1 | A2 | runs-clean | h199 | assigning option over inout option param does not drop old payload: leak
$ `stdlib/core/string.nu`

@ put inout ? String o s x → v { = o @ ?String { T ( string_from x ) } }

@ clear inout ? String o → v { = o @ ?String { F } }

@ main → i {
    : ~ ? String a @ ?String { F }
    ( put a `the first string, long enough for the heap` )
    ( put a `the second string, long enough for the heap` )
    ( clear a )
    ( put a `the third string, long enough for the heap` )
    ?? a { T v → { ( nurl_println ( string_data v ) ) } F → {} }
    ^ 0
}
