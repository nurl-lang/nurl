// diag_ts_dyn_store_methodless_impl_reaches_handle.nu — as
// diag_ts_dyn_store_impl_reaches_handle, but the trait has no methods of
// its own, nor do its supertraits: no dispatch row lists its impls. A
// trait object of it still boxes a value of a type implementing it, and
// one of those holds a share of the channel the value is sent on: a cycle
// of counts nothing frees (docs/MEMORY.md §7.7). The trait's impls are
// what the signature scan met (AGORA-248, CodeRabbit on github#2345).
$ `stdlib/std/channel.nu`

% Tag [T] : Send {}

: Dog { i pitch }

% Tag Dog {}

: Pet { % Tag t }

: Back { ( Channel Pet ) ch }

% Tag Back {}

@ pick i k → ?Pet {
    ? == k 0 { ^ @ ?Pet { F } } {}
    ^ @ ?Pet { T @ Pet { ( dyn Tag @ Dog { k } ) } }
}

@ main → i {
    : ( Channel Pet ) ch ( chan_new [Pet] )
    : ?Pet got ( pick 3 )
    ?? got {
        T p → { ( chan_send [Pet] ch p ) }
        F → {}
    }
    ( chan_close [Pet] ch )
    ^ 0
}
