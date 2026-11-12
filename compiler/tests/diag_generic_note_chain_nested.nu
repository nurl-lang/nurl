// A generic called from inside another generic's instance: the error's
// notes chain, innermost first — the instance the error is in, then the
// one that asked for it, each at the line that did — as C++'s "in
// instantiation of … requested here" (agora #751). The inner instance is
// emitted only after the outer one has finished; it keeps the outer note
// it was queued under.
$ `stdlib/core/vec.nu`
$ `stdlib/std/par.nu`
$ `stdlib/std/rc.nu`

@ outer [A] i n ( @ A i ) f → ( Vec A ) {
    ^ ( par_map_index [A] n 4 f )
}

@ main → i {
    : ( Vec ( Rc i ) ) r ( outer [( Rc i )] 8 \ i k → ( Rc i ) { ^ ( rc_new [i] k ) } )
    ^ 0
}
