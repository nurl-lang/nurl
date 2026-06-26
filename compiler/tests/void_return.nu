// Returning from a `→ v` function: a bare `^` is an early return
// (emits `ret void`), and `^ ( void_call )` tail-returns a void call.
@ note s tag → v { ( nurl_print tag ) ( nurl_print `\n` ) }

@ early i x → v {
    ? > x 0 { ( note `pos` ) ^ } {}
    ( note `nonpos` )
}

@ tail_void i x → v {
    ? > x 0 { ^ ( note `tail-pos` ) } {}
    ( note `tail-nonpos` )
}

@ main → i {
    ( early 5 )
    ( early -1 )
    ( tail_void 5 )
    ( tail_void -1 )
    ^ 0
}
