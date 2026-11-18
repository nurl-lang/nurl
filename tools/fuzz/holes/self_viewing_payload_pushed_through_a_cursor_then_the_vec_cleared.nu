// self_viewing_payload_pushed_through_a_cursor_then_the_vec_cleared: `: ~ ( Vec Tk ) c d  ?? o { T x → ( vec_push [Tk] c x ) }`, then `( vec_clear [Tk] d )` and the pushed element's view read through a slice of d taken before
// AGORA-840 (CodeRabbit on github#1953): refused - the moved payload's view of itself lives in d, which the clear empties
// map: §2.12 | A2 | rejected | - | AGORA-840
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Tk { String text s head }

@ main → i {
    : String t ( string_from `a token text long enough to be on the heap for sure` )
    : ~ Tk tk @ Tk { t `` }
    = . tk head ( string_data . tk text )
    : ~ ? Tk o @ ?Tk { T tk }
    : ~ ( Vec Tk ) d ( vec_new [Tk] )
    : ~ ( Vec Tk ) c d
    ?? o {
        T x → ( vec_push [Tk] c x )
        F → {}
    }
    : s h . ( vec_at [Tk] d 0 ) head
    ( vec_clear [Tk] d )
    ( nurl_println h )
    ^ 0
}
