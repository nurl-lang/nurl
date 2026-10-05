// ts_store_ok.nu — stores into thread-shared state that cannot close a cycle
// compile and run (docs/MEMORY.md §7.7): a channel of channels carrying a
// DIFFERENT type of channel, and a closure capturing a value that leads
// nowhere back.

$ `stdlib/core/string.nu`
$ `stdlib/std/channel.nu`

: Job { ( @ i ) run }

@ main → i {
    : ( Channel ( Channel i ) ) ch ( chan_new [( Channel i )] )
    : ( Channel i ) reply ( chan_new [i] )
    ( chan_send [( Channel i )] ch ( Channel_share [i] reply ) )
    : String tag ( string_from `job` )
    : ( Channel Job ) work ( chan_new [Job] )
    ( chan_send [Job] work @ Job { \ → i { ^ ( string_len tag ) } } )
    ( nurl_print `ok\n` )
    ^ 0
}
