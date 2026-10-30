// vec_reserve_count_near_i64_max: `( tcp_read_into sv buf 9223372036854775807 )` on a one-byte Vec:
// vec_reserve tested `cap < len + n`, which wraps negative, so it reserved
// nothing, and recv(2) — which clamps the count itself — wrote what had
// arrived past the Vec's capacity. The same wrap reached
// tcp_try_read_into, posix_read_append and pfile_read_vec_into.
// Closed: vec_reserve compares the room left (`cap - len`) with `n`, and
// grows to `alloc_count_add len n`, which panics for a sum past i64 max.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | runs-clean | h502 | `( tcp_read_into sv buf 9223372036854775807 )` on a one-byte Vec: vec_reserve tested `cap < len + n`, which wraps negative, so it reserved nothing, and recv(2) — which clamps the count itself —…
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/net.nu`

@ port_of TcpListener l → i {
    : String a ( tcp_local_addr l )
    : i n ( string_len a )
    : ~ i k - n 1
    ~ & > k 0 != ( string_get a k ) 58 { = k - k 1 }
    : ~ i port 0
    : ~ i j + k 1
    ~ < j n {
        = port + * port 10 - ( string_get a j ) 48
        = j + j 1
    }
    ^ port
}

@ main → i {
    ?? ( tcp_listen `127.0.0.1` 0 ) {
        T l → {
            ?? ( tcp_connect `127.0.0.1` ( port_of l ) ) {
                T cl → {
                    : !v NetErr _w ( tcp_write_str cl `0123456789012345678901234567890123456789012345678901234567890123456789` )
                    ?? ( tcp_accept l ) {
                        T sv → {
                            : ( Vec u ) buf ( vec_new [u] )
                            ( vec_push [u] buf # u 65 )
                            ?? ( tcp_read_into sv buf 9223372036854775807 ) {
                                T n → { ( nurl_println_int n ) }
                                F e → { ( nurl_println `read err` ) }
                            }
                        }
                        F e → { ( nurl_println `accept err` ) }
                    }
                }
                F e → { ( nurl_println `connect err` ) }
            }
        }
        F e → { ( nurl_println `listen err` ) }
    }
    ^ 0
}
