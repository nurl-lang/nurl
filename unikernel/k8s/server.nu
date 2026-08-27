// unikernel/k8s/server.nu — one program, two bottom edges.
//
// Built by `build_image.sh` it is a machine: `build_unikernel.sh`
// turns it into a bootable PVH kernel and a hypervisor in the
// container boots it. Built by `build_static_image.sh` it is a 1.5 MB
// static Linux binary in a `FROM scratch` container. Not one line
// below differs between them — what differs is what is underneath,
// which is why `platform` is something the launcher says rather than
// something this file claims.
//
// A Kubernetes container normally holds a process on a shared Linux
// kernel. This one holds a hypervisor holding a machine whose entire
// software stack — scheduler, allocator, TCP/IP, HTTP parser, router —
// is the NURL in this repository. There is no kernel under it, no libc
// beside it, and no init before it: `main` runs because the CPU was
// pointed at it.
//
// Config arrives on the kernel command line, which `cmdenv.c` turns
// into the guest's environment, so the deployment can say `pod=$(POD)`
// the same way it would set an env var on a container.
//
// Routes:
//   GET /         plain text, for a human
//   GET /healthz  liveness/readiness — 200 the moment the loop runs
//   GET /info     JSON, for a machine
//   GET /metrics  Prometheus text
$ `stdlib/std/async.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/env.nu`

// ── shared counters ──────────────────────────────────────────────────
//
// Slot 0 = requests served. A `Vec` is a boxed handle onto a shared
// control block, so every closure that captured it mutates the SAME
// counter — a scalar binding would be captured by value and each
// handler would count its own private zero.

@ stat_get ( Vec i ) c i idx → i {
    ?? ( vec_get [i] c idx ) {
        T n → ^ n
        F → ^ 0
    }
    ^ 0
}

@ stat_bump ( Vec i ) c i idx → i {
    : i n + 1 ( stat_get c idx )
    ( vec_set [i] c idx n )
    ^ n
}

@ uptime_ms i boot_ns → i {
    ^ / - ( monotonic_ns ) boot_ns 1000000
}

// ── handlers ─────────────────────────────────────────────────────────

@ h_root ( Vec i ) c i boot_ns String pod String platform → HttpResponse {
    : i n ( stat_bump c 0 )
    : String b ( string_with_cap 512 )
    ( string_push_str b `NURL HTTP server\n\n` )
    // The same program has two bottom edges, and only one of them gets
    // to make the interesting claim. A build that says "no operating
    // system" while running as a Linux process is a lie the reader
    // cannot check, so the launcher states which one this is and the
    // program says nothing it does not know.
    ? != 0 ( nurl_str_eq ( string_data platform ) `unikernel` ) {
        ( string_push_str b `This reply was assembled by a machine with no operating\n` )
        ( string_push_str b `system. The TCP stack, the HTTP parser and the router are\n` )
        ( string_push_str b `NURL; under them is a virtio-net device and a CPU.\n\n` )
    } {
        ( string_push_str b `Same program, ordinary bottom edge: a Linux process, whose\n` )
        ( string_push_str b `router and HTTP parser are still NURL and whose TCP stack\n` )
        ( string_push_str b `is the node's kernel.\n\n` )
    }
    ( string_push_str b `platform: ` )
    ( string_push_str b ( string_data platform ) )
    ( string_push_str b `\npod:      ` )
    ( string_push_str b ( string_data pod ) )
    ( string_push_str b `\nuptime:   ` )
    ( string_push_str b ( nurl_str_int ( uptime_ms boot_ns ) ) )
    ( string_push_str b ` ms\nrequests: ` )
    ( string_push_str b ( nurl_str_int n ) )
    ( string_push_str b `\n\ntry /healthz, /info, /metrics\n` )
    : HttpResponse r ( response_text 200 ( string_data b ) )
    ( string_free b )
    ^ r
}

@ h_health ( Vec i ) c → HttpResponse {
    ( stat_bump c 0 )
    ^ ( response_text 200 `ok\n` )
}

@ h_info ( Vec i ) c i boot_ns String pod String platform b use_tls → HttpResponse {
    : i n ( stat_bump c 0 )
    : Json j ( json_obj_new )
    ( json_obj_set j `server` ( json_str_lit `nurl-http` ) )
    ( json_obj_set j `pod` ( json_str_lit ( string_data pod ) ) )
    // What is under this program is not something it can find out, so
    // it reports what it was told rather than what it would like to be
    // true: `unikernel` when a hypervisor booted the image, `linux`
    // when the node's kernel exec'd the binary, `unknown` when nobody
    // said.
    ( json_obj_set j `platform` ( json_str_lit ( string_data platform ) ) )
    ( json_obj_set j `tls` ? use_tls ( json_str_lit `1.3` ) ( json_str_lit `none` ) )
    ( json_obj_set j `uptime_ms` ( json_int ( uptime_ms boot_ns ) ) )
    ( json_obj_set j `requests` ( json_int n ) )
    ( json_obj_set j `unix_time` ( json_int ( now_seconds ) ) )
    : HttpResponse r ( response_json 200 j )
    ( json_free j )
    ^ r
}

@ h_metrics ( Vec i ) c i boot_ns → HttpResponse {
    : i n ( stat_bump c 0 )
    : String b ( string_with_cap 256 )
    ( string_push_str b `# HELP nurl_requests_total Requests served since boot.\n` )
    ( string_push_str b `# TYPE nurl_requests_total counter\nnurl_requests_total ` )
    ( string_push_str b ( nurl_str_int n ) )
    ( string_push_str b `\n# HELP nurl_uptime_ms Milliseconds since the guest entered main.\n` )
    ( string_push_str b `# TYPE nurl_uptime_ms gauge\nnurl_uptime_ms ` )
    ( string_push_str b ( nurl_str_int ( uptime_ms boot_ns ) ) )
    ( string_push_str b `\n` )
    : HttpResponse r ( response_text 200 ( string_data b ) )
    ( string_free b )
    ^ r
}

// ── main ─────────────────────────────────────────────────────────────

@ main → i {
    : i boot_ns ( monotonic_ns )
    // One connection at a time is one connection too few.
    //
    // `server_run` accepts, serves keep-alive until the peer goes away
    // or the 30 s idle timeout fires, and only then accepts again. A
    // Kubernetes pod has at least two clients before it has any users
    // — the readiness probe and the liveness probe — and a held-open
    // connection makes every other one wait. That is not a load
    // problem discovered under load: one idle `curl` was enough to
    // time out the kubelet's probes and get the pod replaced.
    //
    // `server_run_async` gives each connection a fiber. On the guest
    // those fibers are the whole concurrency story anyway (one vCPU,
    // cooperative, the device poller is already one of them); hosted,
    // the M:N scheduler spreads them over worker threads. 0 = pick the
    // worker count from the machine.
    ( runtime_init 0 )
    : String pod ( env_var_or `pod` `unnamed` )
    : String platform ( env_var_or `platform` `unknown` )
    : i port ?? ( env_get `port` ) {
        T p → ?? ( string_to_int p ) { T v → v F _ → 8080 }
        F → 8080
    }

    : ( Vec i ) counters ( vec_new [i] )
    ( vec_push [i] counters 0 )

    // TLS when the launcher supplied a certificate, plaintext when it
    // did not. Same program, same routes, same everything above the
    // listener — `tcp_listen_tls` reads two files and the layers below
    // do the rest, and those layers are `stdlib/std/tls.nu`: pure NURL,
    // no libssl, which is why this links into a machine with no
    // operating system at all.
    //
    // Two keys rather than one flag, because a program that is told
    // "use TLS" and then guesses where the certificate lives is a
    // program whose failure mode is a path you cannot see.
    : String cert ( env_var_or `cert` `` )
    : String key ( env_var_or `key` `` )
    : b use_tls && > ( nurl_str_len ( string_data cert ) ) 0 > ( nurl_str_len ( string_data key ) ) 0
    : !TcpListener NetErr lr ? use_tls
    ( tcp_listen_tls `0.0.0.0` port ( string_data cert ) ( string_data key ) )
    ( tcp_listen `0.0.0.0` port )
    ?? lr {
        F e → {
            ( nurl_print `listen failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
        T listener → {
            : Router rt ( router_new )
            ( router_get rt `/`
            \ HttpRequest req Params ps → HttpResponse { ^ ( h_root counters boot_ns pod platform ) } )
            ( router_get rt `/healthz`
            \ HttpRequest req Params ps → HttpResponse { ^ ( h_health counters ) } )
            ( router_get rt `/info`
            \ HttpRequest req Params ps → HttpResponse { ^ ( h_info counters boot_ns pod platform use_tls ) } )
            ( router_get rt `/metrics`
            \ HttpRequest req Params ps → HttpResponse { ^ ( h_metrics counters boot_ns ) } )

            : ( @ HttpResponse HttpRequest ) app
            \ HttpRequest req → HttpResponse { ^ ( router_handle rt req ) }
            : HttpServer srv ( server_new listener app )

            ( nurl_print `nurl unikernel serving on 0.0.0.0:` )
            ( nurl_print ( nurl_str_int port ) )
            ( nurl_print ? use_tls ` (TLS)` `` )
            ( nurl_print `\n` )

            : !v NetErr rr ( server_run_async srv )
            ?? rr {
                T _ → { ( nurl_print `server stopped\n` ) }
                F e → {
                    ( nurl_print `server error: ` )
                    ( nurl_print ( net_err_name e ) )
                    ( nurl_print `\n` )
                }
            }
            ( runtime_shutdown )
            ( router_free rt )
        }
    }
    ( string_free pod )
    ( string_free platform )
    ( string_free cert )
    ( string_free key )
    ( vec_free [i] counters )
    ^ 0
}
