// stdlib/std/par.nu — data-parallel work over an index range, safely.
//
//   ( par_map_index [B] n nt f )   → ( Vec B )   f 0 … f (n-1), on up to
//                                    nt threads; result k is f k
//
// Lane l of nt runs indices l, l+nt, l+2nt, …; each result travels back
// over a channel with its index and lands in its slot, so nothing is
// shared mutably and the answers are the same numbers whatever the
// thread count. `f` runs on several threads at once: what it captures
// must be safe to share (numbers, an Arc of what it reads) — the
// compiler checks that where the closure is built. With nt ≤ 1, or one
// index, it runs in place.
//
// What a batch of independent evaluations (an optimizer's gradient
// stencil, a model per series) needs, and what callers otherwise did by
// handing worker threads raw addresses of their result slots.

$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

: ParOut [B] { i idx B val }

@ par_map_index [B] i n i nt ( @ B i ) f → ( Vec B ) {
    : ( Vec ? B ) slots ( vec_new [? B] )
    : ~ i k 0
    ~ < k n { ( vec_push [? B] slots @ ?B { F } ) = k + k 1 }
    : ~ i lanes ? < nt 1 1 nt
    ? > lanes n { = lanes n } {}
    ? <= lanes 1 {
        = k 0
        ~ < k n { ( vec_put [? B] slots k @ ?B { T ( f k ) } ) = k + k 1 }
    } {
        : ( Channel ( ParOut B ) ) ch ( chan_new [( ParOut B )] )
        : ( Vec Thread ) ts ( vec_new [Thread] )
        : ~ i l 0
        ~ < l lanes {
            : i lane l
            : i stride lanes
            : ( Channel ( ParOut B ) ) cl ( Channel_share [( ParOut B )] ch )
            : ( @ v ) body \ → v {
                : ~ i j lane
                ~ < j n {
                    : b _s ( chan_send [( ParOut B )] cl @ ( ParOut B ) { j ( f j ) } )
                    = j + j stride
                }
            }
            ?? ( thread_spawn_owned body ) {
                T t → { ( vec_push [Thread] ts t ) }
                F _ → {
                    // A spawn that fails runs the lane here.
                    : ~ i j lane
                    ~ < j n { ( vec_put [? B] slots j @ ?B { T ( f j ) } ) = j + j stride }
                }
            }
            = l + l 1
        }
        // Every index the spawned lanes own comes back exactly once.
        : ~ i got 0
        : ~ i want 0
        = k 0
        ~ < k n { ?? ( vec_get [? B] slots k ) { T s → { ?? s { T _ → {} F → { = want + want 1 } } } F → {} } = k + k 1 }
        ~ < got want {
            ?? ( chan_recv [( ParOut B )] ch ) {
                T o → { ( vec_put [? B] slots . o idx @ ?B { T . o val } ) = got + got 1 }
                F → { = got want }
            }
        }
        = l 0
        ~ < l ( vec_len [Thread] ts ) { ?? ( vec_get [Thread] ts l ) { T t → { : i _j ( thread_join t ) } F _ → {} } = l + l 1 }
    }
    : ( Vec B ) out ( vec_with_cap [B] n )
    = k 0
    ~ < k n {
        ?? ( vec_remove [? B] slots 0 ) { T s → { ?? s { T x → { ( vec_push [B] out x ) } F → {} } } F → {} }
        = k + k 1
    }
    ^ out
}
