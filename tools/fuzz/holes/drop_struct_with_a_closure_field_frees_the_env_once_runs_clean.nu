// drop_struct_with_a_closure_field_frees_the_env_once_runs_clean: a struct with a `% Drop` field and a closure field — a closure binding stored in it, and a closure literal written in it — is dropped at its scope's end, and another is moved through a Vec (vec_push, vec_pop, vec_push) and dropped with it.
// Guard for agora #642 item 1: a struct with a drop of its own releases its closure field's env with the rest (its glue); the field is no longer registered for a release of its own besides (mem_register_agg_owned_fields, __agg_drop_takes_fields).
// main 0d1e4d1: accepted, heap-use-after-free in nurl_closure_drop (the env freed twice).
// map: §7.4 | A2 | runs-clean | - | agora #642 item 1 guard: a `% Drop`-holding struct's closure field env is released once, by the struct's drop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

: C { Bomb x ( @ i ) f }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `a tag long enough for the heap` ) k } }

@ main → i {
    : String other ( string_from `a captured string, long enough for the heap` )
    : ( @ i ) clo \ → i { ^ ( string_len other ) }
    : C h @ C { ( bomb 0 ) clo }
    : String other2 ( string_from `another captured string, long enough for the heap` )
    : C h2 @ C { ( bomb 1 ) \ → i { ^ ( string_len other2 ) } }
    : String other3 ( string_from `a third captured string, long enough for the heap` )
    : ( @ i ) clo3 \ → i { ^ ( string_len other3 ) }
    : ~ ( Vec C ) v ( vec_new [C] )
    ( vec_push [C] v @ C { ( bomb 2 ) clo3 } )
    : ?C p ( vec_pop [C] v )
    ?? p { T c → { ( vec_push [C] v c ) } F → {} }
    ( nurl_println ( nurl_str_int ( vec_len [C] v ) ) )
    ^ 0
}
