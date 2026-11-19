// self_viewing_payload_pushed_out_of_its_option_runs_clean: `?? o { T x → ( vec_push [Tk] d x ) }`, x a Tk whose view field views its own String, then the pushed element's view read
// AGORA-840 guard (CodeRabbit on github#1953): accepted - the payload moves into d with its view of itself, which stays live there
// map: §2.12 | A2 | runs-clean | - | AGORA-840
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Tk { String text s head }

@ main → i {
    : String t ( string_from `a token text long enough to be on the heap for sure` )
    : ~ Tk tk @ Tk { t `` }
    = . tk head ( string_data . tk text )
    : ~ ? Tk o @ ?Tk { T tk }
    : ( Vec Tk ) d ( vec_new [Tk] )
    ?? o {
        T x → ( vec_push [Tk] d x )
        F → {}
    }
    ( nurl_println . ( vec_at [Tk] d 0 ) head )
    ^ 0
}
