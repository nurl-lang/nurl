// value_block_tail_call_lending_a_block_local_or_an_outer_binding_runs_clean: the three answers a value block's tail call can give its `:` binding — a lend of a block local (copied), a lend of an outer binding (borrowed), a value of its own (owned).
// Guard for agora #613: the binding's drop flag is the call's own answer OR "it lent a block binding", so a lend of an outer binding must stay a borrow (no double free) and a lend of a block local must still be copied (no use after the block's local goes).
// main 2498b4e: accepted, runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #613 guard: a value block's tail call lending a block local, lending an outer binding, and returning its own value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { ( Vec String ) items }

@ mkw → W { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `an element long enough for a heap buffer` ) ) ^ @ W { v } }

@ gets W w → String { ^ ( vec_at [String] . w items 0 ) }

@ pick String a String b → String { ^ ? > ( string_len a ) 3 a b }

@ main → i {
    : String r { : W w ( mkw ) ( gets w ) }
    ( nurl_println ( string_data r ) )
    : String outer ( string_from `an outer string long enough for a heap buffer` )
    : String q { : String t ( string_from `tt` ) ( pick outer t ) }
    ( nurl_println ( string_data q ) )
    : String q2 { : String t ( string_from `a block string long enough for a heap buffer` ) ( pick t outer ) }
    ( nurl_println ( string_data q2 ) )
    : ~ String z ( string_from `zz` )
    = z { : String t ( string_from `tt` ) ( pick outer t ) }
    ( nurl_println ( string_data z ) )
    ^ 0
}
