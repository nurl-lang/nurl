// h348 through a re-bound reader: `: PNCounter x y` over a binding read out
// of a library handle field views that field, so consuming `x` takes the
// field over and the struct with it — reading the struct after is
// rejected, as when `y` itself is consumed (agora #271).
$ `stdlib/dist/crdt.nu`

: Holder { PNCounter c }

@ eat sink PNCounter x → v { ( pncounter_inc x 1 1 ) }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : PNCounter y . h c
    : PNCounter x y
    ( eat x )
    ^ % ( pncounter_value . h c ) 256
}
