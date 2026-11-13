// arm_tail_join_or_payload_lend_of_an_outer_binding_releases_the_arm_locals_runs_clean: a `?` arm with a local, whose tail is an inner join of two lends out of an outer Vec, or a `??` arm over a lent temporary option whose tail lends its payload, or an outer `: ~` cursor given a lend of an arm local or of an outer Vec and lent by the tail, or a tail call whose argument is a join selecting an arm local or outer bindings; both paths.
// Closed (agora #775 items 4, 5, 6b, 7): an inner join that selects and lends only outer bindings, and a payload whose option is lent out of an outer binding (`__plroot` / `__plend`), are none of the arm's own: its locals go at its exit (mem_arm_outer_lend, __arm_join_lends_outer).
// main 160339c1: the arm's local leaks on each run (definitely lost).
// map: §7.6 | A2 | runs-clean | - | agora #775: an arm whose tail lends only outer bindings releases its locals
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ mk i k → String { ^ ( string_from ( nurl_str_cat ( nurl_str_int k ) ` a heap string long enough` ) ) }

@ idg [T] T x → T { ^ x }

@ mkv → ( Vec String ) { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk 0 ) ) ^ v }

@ join_tail i c → v { : ( Vec String ) v ( mkv ) : String e ? == c 1 { : String a ( mk 4 ) ? == c 1 ( vec_at [String] v 0 ) ( vec_at [String] v 0 ) } ( mk 3 ) ( nurl_println ( string_data e ) ) }

@ payload_tail i c → v { : ( Vec String ) v ( mkv ) : String e ?? ( vec_get [String] v c ) { T p → { : String junk ( mk 5 ) ( idg [String] p ) } F → ( mk 3 ) } ( nurl_println ( string_data e ) ) }

@ cursor_tail i c → v {
    : ~ String cur ( mk 8 )
    : String e ? == c 1 { : ( Vec String ) u ( mkv ) = cur ( vec_at [String] u 0 ) ( idg [String] cur ) } ( mk 3 )
    ( nurl_println ( string_data e ) )
}

@ outer_cursor_tail i c → v {
    : ( Vec String ) w ( mkv )
    : ~ String cur ( mk 8 )
    : String e ? == c 1 { : String junk ( mk 2 ) = cur ( vec_at [String] w 0 ) ( idg [String] cur ) } ( mk 3 )
    ( nurl_println ( string_data e ) )
}

@ join_arg_tail i c → v {
    : String outer ( mk 9 )
    : String e ? == c 1 { : String junk ( mk 2 ) ( idg [String] ? == c 1 outer junk ) } ( mk 3 )
    ( nurl_println ( string_data e ) )
}

@ outer_join_arg_tail i c → v {
    : String outer ( mk 9 )
    : String o2 ( mk 7 )
    : String e ? == c 1 { : String junk ( mk 2 ) ( idg [String] ? == c 1 outer o2 ) } ( mk 3 )
    ( nurl_println ( string_data e ) )
}

@ main → i { ( join_tail 0 ) ( join_tail 1 ) ( payload_tail 0 ) ( payload_tail 1 ) ( cursor_tail 0 ) ( cursor_tail 1 ) ( outer_cursor_tail 0 ) ( outer_cursor_tail 1 ) ( join_arg_tail 0 ) ( join_arg_tail 1 ) ( outer_join_arg_tail 0 ) ( outer_join_arg_tail 1 ) ^ 0 }
