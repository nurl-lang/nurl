// reactor_many_waiters.nu — every fd a fiber waits on is polled, however
// many are waiting (agora #133).
//
// The poll(2) / WSAPoll reactor of the non-Linux targets built its poll
// set into a fixed 256 entries and skipped every waiter past the 255th.
// New waits join its list's head, so the OLDEST were the ones left out:
// with 255 newer fibers waiting, an old one's fd could be ready and its
// fiber never woke. Here 300 fibers wait on 300 UDP sockets; the 45 that
// started waiting first are sent a datagram while the 255 later ones still
// wait (their 3-second timeout far off), and all 45 must wake within 2
// seconds. Before: 0 of 45 (they woke when the newer ones timed out). The
// Linux netpoller always polled them all; this holds the other targets.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
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
    : i n 300
    : i early 45
    ( runtime_init 1 )
    : ~ ( Vec UdpSocket ) socks ( vec_new [UdpSocket] )
    : ~ ( Vec i ) ports ( vec_new [i] )
    : ~ i k 0
    ~ < k n {
        ?? ( udp_bind `127.0.0.1` 0 ) {
            T s → {
                ( vec_push [i] ports ( __port s ) )
                ( vec_push [UdpSocket] socks s )
            }
            F _ → { ( nurl_println `bind failed` ) ^ 1 }
        }
        = k + k 1
    }
    : Atomic woken ( atomic_new 0 )
    // The waiters, oldest first: the first `early` are the ones sent to.
    = k 0
    ~ < k n {
        : i fd ( udp_get_fd ( vec_at [UdpSocket] socks k ) )
        : b first < k early
        : Atomic w ( Atomic_share woken )
        ( spawn_owned \ → v {
            : i rc ( wait_readable fd 3000 )
            ? & first == rc 1 { : i _a ( atomic_add w 1 ) } {}
        } )
        = k + k 1
    }
    : Atomic seen ( Atomic_share woken )
    : ~ i got 0
    ( spawn_owned \ → v {
        ( sleep_ms 100 )  // every waiter parked
        ?? ( udp_bind `127.0.0.1` 0 ) {
            T tx → {
                : ~ i j 0
                ~ < j early {
                    : !i NetErr _s ( udp_send_str_to tx `x` `127.0.0.1` ( vec_at [i] ports j ) )
                    = j + j 1
                }
                : ~ i waited 0
                ~ & < ( atomic_load seen ) early < waited 2000 {
                    ( sleep_ms 10 )
                    = waited + waited 10
                }
                = got ( atomic_load seen )
                ( udp_close tx )
            }
            F _ → {}
        }
    } )
    ( runtime_run )
    ( runtime_shutdown )
    = k 0
    ~ < k n {
        ( udp_close ( vec_at [UdpSocket] socks k ) )
        = k + k 1
    }
    ( nurl_print `oldest woken within 2 s: ` ) ( nurl_print_int got ) ( nurl_print `/` ) ( nurl_println_int early )
    ^ 0
}
