// payload_taken_whole_through_a_match_bound_then_assigned_outward_runs_clean: AGORA-941 guard — a `:` `??` join whose arm takes the payload out (`V x → x`), assigned outward: the payload moved out of `g`, accepted
// map: §7.6 | A2 | runs-clean | - | AGORA-941 guard: a payload taken out by a bound `??` arm, assigned outward
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V String
    Nil
}

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : G g @ G { V ( mk ) }
        : __el ?? g { V x → x Nil → ( mk ) }
        = t __el
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
