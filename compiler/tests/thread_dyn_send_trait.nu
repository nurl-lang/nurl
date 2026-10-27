// thread_dyn_send_trait.nu — a trait object crosses a thread boundary
// when its trait promises it can (agora #127). `% Job [T] : Send` holds
// every impl to Send, so a `%Job` moves into a thread's closure and down
// a channel. The promise reaches through a supertrait: `% Step [T] : Job`
// objects may move because every `Step` type is a `Job` type. `: Send
// Sync` lets one object be reached from several threads at once (the
// `[T: Sync]` bound asks it); `: Send` alone does not.
$ `stdlib/core/marker.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

: Count { i n ( Arc i ) extra }

% Job [T] : Send { @ run T self → i }

% Job Count { @ run Count c → i { ^ + . c n ( arc_get [i] . c extra ) } }

% Step [T] : Job { @ step T self → i }

% Step Count { @ step Count c → i { ^ * 2 . c n } }

: Plain { i n }

% Shared [T] : Send Sync { @ look T self → i }

% Shared Plain { @ look Plain p → i { ^ . p n } }

@ both_sync [T : Sync] T v → i { ^ 1 }

@ both_send [T : Send] T v → i { ^ 1 }

@ main → i {
    : %Job j ( dyn Job @ Count { 40 ( arc_new [i] 2 ) } )
    ?? ( thread_spawn \ → v { ( nurl_print_int ( run j ) ) ( nurl_print `\n` ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }

    : %Step s ( dyn Step @ Count { 21 ( arc_new [i] 0 ) } )
    ?? ( thread_spawn \ → v { ( nurl_print_int ( step s ) ) ( nurl_print `\n` ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }

    : ( Channel % Job ) ch ( chan_new [% Job] )
    ?? ( thread_spawn \ → v {
        ?? ( chan_recv [% Job] ch ) { T got → { ( nurl_print_int ( run got ) ) ( nurl_print `\n` ) } F → {} }
    } ) {
        T t → { ( chan_send [% Job] ch ( dyn Job @ Count { 7 ( arc_new [i] 1 ) } ) ) ( thread_join t ) }
        F _ → {}
    }

    : %Shared p ( dyn Shared @ Plain { 5 } )
    ( nurl_print_int + ( both_sync [% Shared] p ) ( both_send [% Shared] p ) ) ( nurl_print `\n` )
    ^ 0
}
