// unikernel/demos/soak.nu — the question a demo cannot answer: does it
// still work after the thousandth request?
//
// Everything else in this directory proves the machine can do a thing
// once. An appliance is judged on doing it for ever, and the two failure
// modes that only appear at length are both invisible in a single-shot
// test: memory that is handed out and never returned, and a queue whose
// descriptors leak until it runs dry. This program answers requests
// until the host stops asking, and reports what the guest's page
// allocator says about it — a number the guest measures about itself,
// not a guess made from outside.
//
// The verdict is the guest's own: `live` bytes after a warm-up, against
// `live` bytes at the end. Warm-up matters because the first requests
// populate caches, arenas and connection state that are then reused;
// what must not grow is what comes after.
$ `stdlib/std/net.nu`
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

// The guest's page allocator, as seen from NURL. 0 = bytes live now,
// 1 = the high-water mark, 2 = bytes still available, 3 = the largest
// hole, 4 = bytes lost to a full free list, 5 = the number of holes.
// Guest-only: on Linux this program does not link, which is the honest
// outcome for a question only this machine can answer.
& `c` @ nurl_guest_mem i which → i

@ warmup_at → i { ^ 20 }

@ serve_until → i { ^ 200 }

@ __kib i bytes → i { ^ / bytes 1024 }

@ __report s label i live → v {
    ( nurl_print label )
    ( nurl_print ( nurl_str_int ( __kib live ) ) )
    ( nurl_print ` KiB\n` )
    ( flush )
}

@ main → i {
    ?? ( tcp_listen `0.0.0.0` 8080 ) {
        F e → {
            ( nurl_print `listen failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
        T l → {
            ( nurl_print `soak: listening on 8080\n` )
            ( flush )
            : ~ i answered 0
            : ~ i failures 0
            : ~ i live_warm 0
            ~ && < answered ( serve_until ) < failures 8 {
                ?? ( tcp_accept l ) {
                    F _e → = failures + failures 1
                    T c → {
                        ?? ( tcp_read_chunk c 2048 ) {
                            T req → ( vec_free [u] req )
                            F _e → {}
                        }
                        : !v NetErr w ( tcp_write_str c `HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n` )
                        ?? w {
                            T _ → = answered + answered 1
                            F _e → = failures + failures 1
                        }
                        ( tcp_close_conn c )
                        ? == answered ( warmup_at ) {
                            = live_warm ( nurl_guest_mem 0 )
                            ( __report `soak: live after warm-up: ` live_warm )
                        } {}
                    }
                }
            }
            ( tcp_close_listener l )

            : i live_end ( nurl_guest_mem 0 )
            : i peak ( nurl_guest_mem 1 )
            : i lost ( nurl_guest_mem 4 )
            ( nurl_print `soak: answered ` )
            ( nurl_print ( nurl_str_int answered ) )
            ( nurl_print ` requests\n` )
            ( __report `soak: live at the end: ` live_end )
            ( __report `soak: high-water: ` peak )
            ( nurl_print `soak: bytes lost to a full free list: ` )
            ( nurl_print ( nurl_str_int lost ) )
            ( nurl_print `\n` )
            // The verdict, decided here rather than by the harness: the
            // guest is the only party that can see its own heap, and a
            // number in the output that nobody compares is a number
            // nobody checks. One page of slack — an allocator whose
            // arenas are megabytes cannot land on the same byte twice
            // for reasons that have nothing to do with a leak.
            : i growth ? > live_end live_warm - live_end live_warm 0
            ? && == lost 0 <= growth 4096 {
                ( nurl_print `soak: verdict STABLE (growth ` )
                ( nurl_print ( nurl_str_int growth ) )
                ( nurl_print ` bytes over ` )
                ( nurl_print ( nurl_str_int - answered ( warmup_at ) ) )
                ( nurl_print ` requests)\n` )
            } {
                ( nurl_print `soak: verdict GROWING (growth ` )
                ( nurl_print ( nurl_str_int growth ) )
                ( nurl_print ` bytes, lost ` )
                ( nurl_print ( nurl_str_int lost ) )
                ( nurl_print `)\n` )
            }
        }
    }
    ( flush )
    ^ 0
}
