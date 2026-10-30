// map_keys_of_owned_keys: `map_keys` over String keys leaked every key and left the map holding empty ones: a key read through the map's slot pointer and pushed into the result was both copied (vec_push keeps it) and emptied from its slot (vec_push consumes it), so the original went nowhere.
// Closed: a value read through a pointer and handed to a callee that keeps a copy is not also emptied where it lives (gen_call, the `arg_faddr` path): only a callee that consumes it without storing a copy takes it out, as for a struct field.
// main (before this PR): LeakSanitizer reported the key String (24 bytes) and its bytes leaked.
// map: §7.6 | A2 | runs-clean | h303 | map_keys over String keys: a key read through the slot pointer was both copied into the Vec and emptied from its slot — leak, and the map lost the key
$ `stdlib/std/hashmap.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i String ) hs \ String k → i { ^ ( hash_string ( string_data k ) ) }
    : ( @ b String String ) es \ String a String b → b { ^ ( string_eq a b ) }
    : ( HashMap String i ) m ( map_new [String i] )
    ( map_set [String i] m ( string_from `alpha` ) 1 hs es )
    : ( Vec String ) ks ( map_keys [String i] m )
    ( nurl_println_int ( vec_len [String] ks ) )
    : ?i got ( map_get [String i] m ( string_from `alpha` ) hs es )
    ?? got { T n → { ( nurl_println_int n ) } F → { ( nurl_println `lost` ) } }
    ^ 0
}
