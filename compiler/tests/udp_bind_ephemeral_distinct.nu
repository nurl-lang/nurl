// udp_bind_ephemeral_distinct.nu — every `udp_bind host 0` is given a
// port no other socket holds.
//
// UDP sockets were bound with SO_REUSEADDR, the option a TCP listener
// takes for TIME_WAIT. On a UDP socket it lets sockets share a port, and
// the ephemeral allocator then handed out ports already held: of 900 binds
// on 127.0.0.1, several shared a port in every run (one in five runs of
// 300), and a datagram sent to one socket's port reached the other — found
// as a "lost wakeup" by reactor_many_waiters (agora #133). It also let any
// program bind a running server's UDP port beside it.

$ `stdlib/std/udp.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ __port UdpSocket s → i {
    : String address ( udp_local_addr s )
    : ~ i port 0
    : ~ i k 0
    ~ < k ( string_len address ) {
        : i ch ( string_get address k )
        ? == ch 58 { = port 0 } { ? & >= ch 48 <= ch 57 { = port + * port 10 - ch 48 } {} }
        = k + k 1
    }
    ^ port
}

@ main → i {
    : i n 900
    : ~ ( Vec UdpSocket ) socks ( vec_new [UdpSocket] )
    : ~ ( Vec i ) seen ( vec_new [i] )
    : ~ i k 0
    ~ < k 65536 { ( vec_push [i] seen 0 ) = k + k 1 }
    : ~ i dup 0
    = k 0
    ~ < k n {
        ?? ( udp_bind `127.0.0.1` 0 ) {
            T s → {
                : i p ( __port s )
                ? > ( vec_at [i] seen p ) 0 { = dup + dup 1 } {}
                : b _w ( vec_set [i] seen p 1 )
                ( vec_push [UdpSocket] socks s )
            }
            F _ → { ( nurl_println `bind failed` ) ^ 1 }
        }
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [UdpSocket] socks ) {
        ( udp_close ( vec_at [UdpSocket] socks k ) )
        = k + k 1
    }
    ( nurl_print `ports shared: ` ) ( nurl_println_int dup )
    ^ 0
}
