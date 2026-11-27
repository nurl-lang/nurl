// ts_dyn_store_ok.nu — a value that holds a trait object, out of a join (an
// option's payload: what its closures capture cannot be followed), sent on
// a channel. Whether it can lead back to the channel is decided by the types
// that implement the trait (docs/MEMORY.md §7.7, AGORA-248): Dog holds a
// number, so no cycle; it compiles and runs.
$ `stdlib/std/channel.nu`

% Speaker [T] : Send { @ speak T self → i }

: Dog { i pitch }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

: Pet { % Speaker s }

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
    : ?Pet back ( chan_recv [Pet] ch )
    : i n ?? back { T q → ( speak . q s ) F → 0 }
    ( chan_close [Pet] ch )
    ( nurl_println_int n )
    ^ 0
}
