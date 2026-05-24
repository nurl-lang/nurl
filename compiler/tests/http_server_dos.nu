// http_server_dos.nu — DoS connection-cap regression.
//
// Live (NURL_NET_TESTS=1): spin up a server with max_concurrent=2,
// max_per_ip=2. Open 4 concurrent TCP connections from python; the
// first 2 are accepted and receive a response, the last 2 hit the
// per-IP cap and are closed before the server speaks.
//
// Verification: count how many of the 4 conns receive any data on
// the read. accepted_count must equal 2 (cap value).

$ `stdlib/std/net.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s tag s value → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ dos_handler HttpRequest req → HttpResponse {
    // Sleep a moment so concurrent connections actually overlap.
    ( sleep_ms 250 )
    ^ ( response_text 200 `dos-ok` )
}

@ run_live_dos_test → v {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18793 16 )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( dos_handler req ) }
            : DosLimits dl @ DosLimits { 2 2 }
            : HttpServer srv ( server_new_with_dos listener h dl )

            // Spawn a 3-worker pool so we can actually accept three
            // overlapping conns. The 4th is bounced by the per-IP cap.
            : ( @ v ) worker_fn \ → v {
                : !v NetErr r ( server_run_once srv )
                ?? r { T _ → {} F _ → {} }
            }
            // Spawn 4 acceptors (one per expected conn)
            : !Thread ThreadErr t1 ( thread_spawn worker_fn )
            : !Thread ThreadErr t2 ( thread_spawn worker_fn )
            : !Thread ThreadErr t3 ( thread_spawn worker_fn )
            : !Thread ThreadErr t4 ( thread_spawn worker_fn )

            ( sleep_ms 50 )

            // Fire 4 simultaneous HTTP/1.0 GETs via python; each conn
            // reports how many bytes it received (rejected conns get 0).
            : s py
            `python3 -c "import socket,threading,sys
results=[0]*4
def go(i):
    try:
        s=socket.socket(); s.settimeout(2)
        s.connect(('127.0.0.1',18793))
        s.sendall(b'GET / HTTP/1.0\\r\\nHost: t\\r\\n\\r\\n')
        buf=b''
        while True:
            try:
                c=s.recv(4096)
            except Exception:
                break
            if not c: break
            buf+=c
        results[i]=len(buf)
        s.close()
    except Exception as e:
        results[i]=0
ts=[threading.Thread(target=go,args=(i,)) for i in range(4)]
for t in ts: t.start()
for t in ts: t.join()
n_accepted = sum(1 for r in results if r>0)
n_rejected = sum(1 for r in results if r==0)
print(f'accepted={n_accepted}')
print(f'rejected={n_rejected}')
" 2>&1`
            : !Output ProcessErr pr ( process_run_shell py )
            ?? pr {
                T po → {
                    ( nurl_print ( output_stdout po ) )
                    ( output_free po )
                }
                F pe → ( println_label `client_err` ( process_err_name pe ) )
            }

            : i _j1 ( thread_join_safe t1 )
            : i _j2 ( thread_join_safe t2 )
            : i _j3 ( thread_join_safe t3 )
            : i _j4 ( thread_join_safe t4 )
            ( server_stop srv )
        }
        F e → ( println_label `listen` ( net_err_name e ) )
    }
}

@ thread_join_safe !Thread ThreadErr tr → i {
    ?? tr {
        T th → ( thread_join th )
        F _ → 0
    }
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            ( run_live_dos_test )
        }
        F → { ( nurl_print `live DoS test skipped (NURL_NET_TESTS != 1)\n` ) }
    }
    ^ 0
}
