// ts_dyn_store_no_impl.nu — a value that holds a trait object of a trait no
// type implements (here an option of one, always empty), out of a join, sent
// on a channel. A trait no type implements has no object, so the value can
// hold no closure and no handle through it (docs/MEMORY.md §7.7, AGORA-248):
// it compiles and runs. (stdlib/std/net.nu's TcpConnImpl, given a field of
// a transport object in a program with no transport impl, is the case.)
$ `stdlib/std/channel.nu`

% Quiet [T] : Send { @ hush T self → i }

: Slot { ? % Quiet q i n }

@ pick i k → ?Slot {
    ? == k 0 { ^ @ ?Slot { F } } {}
    ^ @ ?Slot { T @ Slot { @ ?% Quiet { F } k } }
}

@ main → i {
    : ( Channel Slot ) ch ( chan_new [Slot] )
    : ?Slot got ( pick 5 )
    ?? got {
        T p → { ( chan_send [Slot] ch p ) }
        F → {}
    }
    : ?Slot back ( chan_recv [Slot] ch )
    : i n ?? back { T q → . q n F → 0 }
    ( chan_close [Slot] ch )
    ( nurl_println_int n )
    ^ 0
}
