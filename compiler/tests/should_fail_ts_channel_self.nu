// should_fail_ts_channel_self.nu — a channel whose queue holds a value of
// its own type sent into itself keeps itself alive (docs/MEMORY.md §7.7).

$ `stdlib/std/channel.nu`

: Box2 { ( Channel Box2 ) back i n }

@ main → i {
    : ( Channel Box2 ) ch ( chan_new [Box2] )
    ( chan_send [Box2] ch @ Box2 { ( Channel_share [Box2] ch ) 1 } )
    ^ 0
}
