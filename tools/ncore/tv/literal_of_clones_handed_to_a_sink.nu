// tvdrops selftest program: `give` moves two clones of vv's elements into a
// literal and hands the literal to `keep`, which takes it (a `sink`: it is
// pushed into `out`): what the literal carries goes with it
$ `stdlib/core/vec.nu`

: Two { ( Vec i ) a ( Vec i ) b }

@ keep ( Vec Two ) out Two t → v { ( vec_push [Two] out t ) }

@ give ( Vec Two ) out ( Vec ( Vec i ) ) vv → v { ( keep out @ Two { ( vec_at [( Vec i )] vv 0 ) ( vec_at [( Vec i )] vv 1 ) } ) }

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    : ( Vec Two ) out ( vec_new [Two] )
    ( give out vv )
    ^ ( vec_len [Two] out )
}
