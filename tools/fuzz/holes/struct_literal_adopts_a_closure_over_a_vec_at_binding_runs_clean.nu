// struct_literal_adopts_a_closure_over_a_vec_at_binding_runs_clean: agora #483 — a struct literal's closure field adopts a closure over a `vec_at` binding: the env copies the String in, and outlives the Vec
// The shape the fix must keep: an adopted closure owns its copy (agora #483).
// main 21a0fb5: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #483: a struct literal adopts a closure over a vec_at binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( @ i ) cb i pad }

@ main → i {
    : ~ H keep @ H { \ → i { ^ 0 } 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string its vector frees; the struct's closure holds its own copy` ) )
        : String e ( vec_at [String] t 0 )
        = keep @ H { \ → i { ^ ( strlen ( string_data e ) ) } 0 }
    }
    : ( @ i ) g . keep cb
    ( nurl_println_int ( g ) )
    ^ 0
}
