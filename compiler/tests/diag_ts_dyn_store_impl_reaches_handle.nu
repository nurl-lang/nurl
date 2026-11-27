// diag_ts_dyn_store_impl_reaches_handle.nu — a value that holds a trait
// object, out of a join, sent on a channel, where one type implementing the
// trait holds a share of that very channel: the value can lead back to the
// channel, a cycle of counts nothing frees (docs/MEMORY.md §7.7). Deciding
// by the trait's impls (AGORA-248) still refuses it.
$ `stdlib/std/channel.nu`

% Speaker [T] : Send { @ speak T self → i }

: Dog { i pitch }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

: Pet { % Speaker s }

: Back { ( Channel Pet ) ch i n }

% Speaker Back { @ speak Back b → i { ^ . b n } }

@ pick i k → ?Pet {
    ? == k 0 { ^ @ ?Pet { F } } {}
    ^ @ ?Pet { T @ Pet { ( dyn Speaker @ Dog { k } ) } }
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
