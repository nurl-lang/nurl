// fresh_cat_of_a_local_view_in_a_parked_walk_runs_clean: a function hands back nurl_str_cat3 of a view of its own String; its walk is parked, and an `unsafe` generic's instance compiles last.
// Kept: a parked walk runs after the module, in its own function's trust context (bck_defer_fn's `u`), not the last function compiled's. Read in an `unsafe` one's, the view was an owner, and the fresh string a view of the local.
// main 0032747 (Family G, github#1609): rejected, as unikernel/net/sockets.nu's __addr_string was in the simulation gate; 0f24558, before it: runs clean.
// map: §2.13 | A2 | runs-clean | - | a fresh string built from a view of a local String, handed back by a function whose walk is parked, an unsafe instance compiled last
$ `stdlib/core/string.nu`
$ `stdlib/core/mem.nu`

// (`note`, compiled after `addr`, is handed a binding: `addr`'s walk is
// parked until the module has compiled.)
@ addr i port → s {
    : String host ( string_from `127.0.0.1` )
    : s a ( nurl_str_cat3 ( string_data host ) `:` ( nurl_str_int port ) )
    ( note host )
    ^ a
}

@ note String s → v { ( nurl_println ( string_data s ) ) }

// (`put [i]`, instantiated after the parse, asks for `mem_replace [i]`, an
// `unsafe` generic's instance: the last function compiled.)
@ put [T] inout T place sink T x → T { ^ ( mem_replace [T] place x ) }

@ main → i {
    : String w ( string_adopt ( addr 8080 ) )
    ( nurl_println ( string_data w ) )
    : ~ i k 1
    : i old ( put [i] k 0 )
    ^ - + old k 1
}
