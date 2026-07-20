// packages/swarm-mcp/src/main.nu — swarm-mcp: an MCP-controlled distributed
// compute engine. A language model sets a workload over MCP — an expression
// kernel in `x` plus a range and a reduce op — and the cluster evaluates it
// distributed; the model reads running tasks and finished results back.
//
//   swarm-mcp relay  0.0.0.0 47700 [--v]   # the meeting point (one per cluster)
//   swarm-mcp worker <host> <port>         # join as a compute node
//   swarm-mcp mcp    <host> <port>         # MCP server (stdio) → drives the cluster
//   swarm-mcp submit <host> <port> <reduce> <lo> <hi> <expr>   # manual CLI submit
//
// The cluster layer (membership → ring → job dispatch) is the swarm package's;
// here every worker registers ONE generic kernel handler (work.nu) that
// interprets the submitted expression (expr.nu), so any normal-operation
// workload runs without recompiling a worker. Phase 2 swaps the interpreter for
// a NURL→wasm kernel; the protocol and MCP surface stay the same.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/job.nu`
$ `stdlib/ext/http_cli.nu`
$ `token.nu`
$ `blob.nu`
$ `census.nu`
$ `expr.nu`
$ `work.nu`
$ `wasmkernel.nu`
$ `buildwasm.nu`
$ `cudakernel.nu`

@ swarm_vnodes → i { ^ 64 }

@ kind_kernel → i { ^ 1 }

// A 32-byte opaque routing pubkey derived deterministically from a node id.
@ pk_from_id i id → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i s id
    : ~ i k 0
    ~ < k 32 {
        = s + + * s 1103515245 12345 k
        ( vec_push [u] v # u & >> s 16 255 )
        = k + k 1
    }
    ^ v
}

// ── node bundle (the cluster coordinator/worker state) ───────────

: Swarm {
    s transport  // *Transport
    s ring  // *Ring
    s gpu_ring  // *Ring — the GPU capability domain (cap_gpu workers only)
    s roster  // *Roster
    s job  // *JobNode
    ( Vec u ) self_pk
    i self_id
    i role
    i self_caps  // capability bits this node advertises (cap_gpu for --gpu workers)
    ( Vec u ) group  // token-derived 32-byte relay multicast group (cluster isolation)
    ( Vec u ) key  // token-derived HMAC key (compute authenticity)
    i epoch  // bumps on every ring-membership change (block-seed invalidation)
}

@ swarm_new RelayClient rc i id i role i caps s token → *Swarm {
    : ( Vec u ) me ( pk_from_id id )
    : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
    : *Ring ring ( ring_new )
    : *Ring gring ( ring_new )
    : *Roster roster ( roster_new )
    : *JobNode jn ( job_node_new # s tr # s ring me id )
    // GPU wasm chunks route/own/forward on the GPU capability ring — every
    // node scopes the kind the same way, so mid-flight re-homing stays inside
    // the domain (dist/job job_set_ring).
    ( job_set_ring jn ( kind_wasm_gpu ) # s gring )
    // Block seeds must land on the SAME worker as the compute chunk that
    // references them: same ring, same key -> same owner.
    ( job_set_ring jn ( kind_blob ) # s gring )
    : *Swarm sw # *Swarm ( nurl_alloc Z Swarm )
    = . sw transport # s tr
    = . sw ring # s ring
    = . sw gpu_ring # s gring
    = . sw roster # s roster
    = . sw job # s jn
    = . sw self_pk me
    = . sw self_id id
    = . sw role role
    = . sw self_caps caps
    = . sw epoch 0
    = . sw group ( token_group_id token )
    = . sw key ( token_key token )
    ? == role ( role_worker ) {
        ( roster_add roster ring me id ( swarm_vnodes ) caps )
        ? == & caps ( cap_gpu ) ( cap_gpu ) { ( ring_add_member gring me ( swarm_vnodes ) ) } {}
    } {}
    ^ sw
}

@ swarm_free * Swarm sw → v {
    ( job_node_free # *JobNode . sw job )
    ( ring_free # *Ring . sw ring )
    ( ring_free # *Ring . sw gpu_ring )
    ( roster_free # *Roster . sw roster )
    ( transport_free # *Transport . sw transport )
    ( vec_free [u] . sw self_pk )
    ( vec_free [u] . sw group )
    ( vec_free [u] . sw key )
    ( nurl_free # s sw )
}

@ swarm_join_group * Swarm sw → v {
    ?? ( transport_group_join # *Transport . sw transport . sw group ) { T _ → {} F _ → {} }
}

@ swarm_announce * Swarm sw i want → v {
    : b _ok ( swarm_announce_ok sw want )
}

// Announce presence; returns whether the broadcast reached the relay. A
// failed send is the reconnect loop's signal that the relay is gone.
@ swarm_announce_ok * Swarm sw i want → b {
    : ( Vec u ) msg ( hello_build . sw self_id . sw role want . sw self_pk . sw self_caps )
    : ~ b ok F
    ?? ( transport_broadcast # *Transport . sw transport . sw group msg ) { T _ → { = ok T } F _ → {} }
    ( vec_free [u] msg )
    ^ ok
}

@ swarm_on_hello * Swarm sw Hello h → v {
    ? == . h role ( role_worker ) {
        ? ( roster_add # *Roster . sw roster # *Ring . sw ring . h pubkey . h id ( swarm_vnodes ) . h caps ) {
            // A newly-heard GPU-capable worker also joins the GPU domain ring
            // (idempotent via the roster gate — a re-heard HELLO adds nothing).
            ? == & . h caps ( cap_gpu ) ( cap_gpu ) { ( ring_add_member # *Ring . sw gpu_ring . h pubkey ( swarm_vnodes ) ) } {}
            // ring changed -> chunk keys may re-home; block seeds recorded
            // under the old epoch are stale and will re-seed once
            = . sw epoch + . sw epoch 1
        } {}
        ( transport_add_peer # *Transport . sw transport . h pubkey )
    } {}
    ? & == . h want 1 ! ( bytes_eq . h pubkey . sw self_pk ) {
        : ( Vec u ) reply ( hello_build . sw self_id . sw role 0 . sw self_pk . sw self_caps )
        ?? ( transport_send # *Transport . sw transport . h pubkey reply ) { T _ → {} F _ → {} }
        ( vec_free [u] reply )
    } {}
}

@ swarm_pump * Swarm sw i max → v {
    : ~ b more T
    ~ more {
        ?? ( transport_recv # *Transport . sw transport max ) {
            T tm → {
                : i b0 ?? ( vec_get [u] . tm payload 0 ) { T x → # i x F → 255 }
                ? == b0 ( census_hello_t ) {
                    : Hello h ( hello_decode . tm payload )
                    ( swarm_on_hello sw h )
                    ( hello_free h )
                } {
                    : JobMsg m ( jobmsg_decode . tm payload )
                    ? == . m mtype ( job_submit_t ) { ( job_on_submit # *JobNode . sw job m ) } {}
                    ? == . m mtype ( job_result_t ) { ( job_on_result # *JobNode . sw job m ) } {}
                    ( jobmsg_free m )
                }
                ( transport_msg_free tm )
            }
            F → { = more F }
        }
    }
}

@ swarm_discover * Swarm sw i rounds → v {
    ( swarm_announce sw 1 )
    : ~ i t 0
    ~ < t rounds { ( swarm_pump sw 200 ) = t + t 1 }
}

// ── role threads ─────────────────────────────────────────────────
// Each enabled role runs its own blocking event loop on its own OS thread,
// talking to the rest of the cluster over the relay (loopback when the relay is
// co-located). This mirrors the proven separate-process topology while
// presenting a single command. Only the relay role drives the fiber reactor
// (runtime_run); worker/coordinator roles do ordinary blocking I/O off the
// reactor, so heavy compute or a TLS handshake never stalls the relay.

// Dial the relay, retrying briefly so a co-located relay that is still binding
// (or a relay that restarts) doesn't lose its local roles to a startup race.
// ── relay endpoint list (failover) ───────────────────────────────
// --connect accepts a comma-separated list "h1:p1,h2:p2,…"; any one being
// reachable bootstraps the node, and if the connected relay dies the node
// rotates to the next. A single endpoint is just a one-element list.
// The list is kept as raw "host:port" String segments (default filled in
// when a segment omits either); parse_hostport resolves one at dial time.
@ parse_relay_list String cs s dhost i dport → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( string_len cs )
    : s d ( string_data cs )
    : ~ i start 0
    : ~ i k 0
    ~ <= k n {
        ? | == k n == ( nurl_str_get d k ) 44 {
            ? > k start { ( vec_push [String] out ( string_substr cs start - k start ) ) } {}
            = start + k 1
        } {}
        = k + k 1
    }
    ? == ( vec_len [String] out ) 0 {
        : String def ( string_new )
        ( string_push_str def dhost )
        ( string_push_char def 58 )
        ( string_push_str def ( nurl_str_int dport ) )
        ( vec_push [String] out def )
    } {}
    ^ out
}

@ relay_list_free ( Vec String ) lst → v {
    : ~ i k 0
    ~ < k ( vec_len [String] lst ) {
        ?? ( vec_get [String] lst k ) { T seg → { ( string_free seg ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] lst )
}

@ relay_dial_retry s host i port i tries → !RelayClient NetErr {
    ?? ( relay_dial host port ) {
        T rc → { ^ @ !RelayClient NetErr { T rc } }
        F e → {
            ? <= tries 1 { ^ @ !RelayClient NetErr { F e } } {}
            ( sleep_ms 150 )
            ^ ( relay_dial_retry host port - tries 1 )
        }
    }
}

// RELAY role: the dumb rendezvous point. Owns the fiber reactor on this thread.
@ node_relay s host i port i vflag → v {
    ?? ( relay_server_start host port ) {
        T rs → {
            : *RelayServer p # *RelayServer ( nurl_alloc Z RelayServer )
            = . p lst . rs lst
            = . p clients . rs clients
            = . p groups . rs groups
            = . p verbose vflag
            ( relay_server_run p )
            ( relay_server_free p )
        }
        F e → { ( nurl_eprintln `swarm-mcp: relay failed to bind (port in use?)` ) }
    }
}

// WORKER role: join the cluster, register the kernel + wasm handlers (every
// worker can run wasm modules), and drain cluster traffic forever. Each worker
// thread takes a fresh random identity, so `--workers N` spins up N independent
// ring members in one process. gpu≠0: advertise cap_gpu and register the
// kind_wasm_gpu handler — wasm chunks of that kind run with --allow-gpu.
// A worker keeps its identity across reconnects (same ring member) and, when
// the relay it is on dies, rotates to the next relay in the list and
// re-forms — no single relay is a point of failure. Death is detected by a
// periodic heartbeat announce whose SEND fails when the relay is gone; the
// on-disk block cache survives the switch, so re-seeding is idempotent.
@ node_worker ( Vec String ) relays s dhost i dport s token i vflag i gpu → v {
    : i id ( rand_u64 )
    : *u idxc ( nurl_alloc 8 )
    ( nurl_poke idxc 0 0 )
    : i caps ? != gpu 0 ( cap_gpu ) 0
    : ~ i from 0
    : ~ b keep T
    ~ keep {
        ?? ( relay_dial_list relays dhost dport from idxc ) {
            F _ → {
                ( nurl_eprintln `swarm-mcp: worker could not reach any relay in the list — retrying` )
                ( sleep_ms 1000 )
            }
            T rc → {
                : i cur ( nurl_peek idxc 0 )
                = from % + cur 1 ( vec_len [String] relays )
                : ( Vec u ) reg ( pk_from_id id )
                ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
                ( vec_free [u] reg )
                ( relay_set_timeout rc 250 )
                : *Swarm sw ( swarm_new rc id ( role_worker ) caps token )
                ( job_register # *JobNode . sw job ( kind_kernel ) ( kernel_handler . sw key ) )
                ( job_register # *JobNode . sw job ( kind_wasm ) ( wasm_handler . sw key ) )
                ( job_register # *JobNode . sw job ( kind_blob ) ( blob_handler . sw key ) )
                ? != gpu 0 { ( job_register # *JobNode . sw job ( kind_wasm_gpu ) ( wasm_gpu_handler . sw key ) ) } {}
                ( swarm_join_group sw )
                ( swarm_announce sw 1 )
                ? == vflag 1 { ( nurl_print `swarm-mcp worker ` ) ( nurl_print ( nurl_str_int id ) ) ( nurl_print ` on relay ` ) ( nurl_print ( nurl_str_int cur ) ) ( nurl_print ? != gpu 0 ` ready (gpu)\n` ` ready\n` ) } {}
                // pump; a heartbeat every ~2 s doubles as the relay-liveness
                // probe (its send fails when the relay is gone)
                : ~ b live T
                : ~ i beat 0
                ~ live {
                    ( swarm_pump sw 200 )
                    = beat + beat 1
                    ? >= beat 10 {
                        = beat 0
                        ? ( swarm_announce_ok sw 1 ) {} { = live F }
                    } {}
                    ( sleep_ms 5 )
                }
                ? == vflag 1 { ( nurl_print `swarm-mcp worker ` ) ( nurl_print ( nurl_str_int id ) ) ( nurl_print ` lost its relay — reconnecting\n` ) } {}
                ( swarm_free sw )
                ( relay_close rc )
            }
        }
    }
    ( nurl_free idxc )
}

// ── shared submit: shard an expr task across the cluster ──────────
// Submits the kernel to the ring and returns the chunk task-ids. `expr` is the
// raw kernel bytes; the caller owns it.

@ cluster_submit * Swarm sw i op i dtype i lo i hi ( Vec u ) expr i nchunks → ( Vec i ) {
    : ( Vec s ) chunks ( shard lo hi nchunks )
    : ( Vec i ) tids ( vec_new [i] )
    : ~ i i 0
    ~ < i nchunks {
        : s cp ?? ( vec_get [s] chunks i ) { T x → x F → # s 0 }
        : *Chunk c # *Chunk cp
        : ( Vec u ) rkey ( chunk_key i )
        : ( Vec u ) payload ( chunk_payload op dtype . c lo . c hi expr )
        : ( Vec u ) tagged ( token_tag . sw key payload )
        ( vec_push [i] tids ( job_submit # *JobNode . sw job ( kind_kernel ) rkey tagged ) )
        ( vec_free [u] rkey ) ( vec_free [u] payload ) ( vec_free [u] tagged )
        = i + i 1
    }
    ( shard_free chunks )
    ^ tids
}

// Shard a wasm-kernel task: ship the compiled module + each sub-range to its
// ring owner under `kind` (kind_wasm, or kind_wasm_gpu — the GPU capability
// domain). The module bytes ride every chunk (workers cache by content hash,
// so it is written once per worker).
@ cluster_submit_wasm * Swarm sw i lo i hi ( Vec u ) wasm i nchunks i kind → ( Vec i ) {
    : ( Vec s ) chunks ( shard lo hi nchunks )
    : ( Vec i ) tids ( vec_new [i] )
    : ~ i i 0
    ~ < i nchunks {
        : s cp ?? ( vec_get [s] chunks i ) { T x → x F → # s 0 }
        : *Chunk c # *Chunk cp
        : ( Vec u ) rkey ( chunk_key i )
        : ( Vec u ) payload ( wasm_chunk_payload . c lo . c hi wasm )
        : ( Vec u ) tagged ( token_tag . sw key payload )
        ( vec_push [i] tids ( job_submit # *JobNode . sw job kind rkey tagged ) )
        ( vec_free [u] rkey ) ( vec_free [u] payload ) ( vec_free [u] tagged )
        = i + i 1
    }
    ( shard_free chunks )
    ^ tids
}

// Shard a GPU task (payload v2/v3): mode, K, runtime params and the module
// ride every chunk under kind_wasm_gpu — routed on the GPU capability ring.
// `data` is the WHOLE dataset's raw LE f64 bytes (empty when the task has no
// dataset); each chunk ships exactly its own slice data[clo·8, chi·8) — the
// split travels with its task, so a worker needs no separate fetch.
@ cluster_submit_wasm_gpu * Swarm sw i mode i lo i hi i kbins ( Vec i ) params ( Vec u ) data ( Vec u ) wasm i nchunks → ( Vec i ) {
    : b hasdata > ( vec_len [u] data ) 0
    : ( Vec s ) chunks ( shard lo hi nchunks )
    : ( Vec i ) tids ( vec_new [i] )
    : ~ i i 0
    ~ < i nchunks {
        : s cp ?? ( vec_get [s] chunks i ) { T x → x F → # s 0 }
        : *Chunk c # *Chunk cp
        : ( Vec u ) rkey ( chunk_key i )
        : ( Vec u ) slice ? hasdata ( bytes_slice data * . c lo 8 * . c hi 8 ) ( vec_new [u] )
        : ( Vec u ) payload ( wasm_gpu_chunk_payload mode . c lo . c hi kbins params slice wasm )
        : ( Vec u ) tagged ( token_tag . sw key payload )
        ( vec_push [i] tids ( job_submit # *JobNode . sw job ( kind_wasm_gpu ) rkey tagged ) )
        ( vec_free [u] rkey ) ( vec_free [u] slice ) ( vec_free [u] payload ) ( vec_free [u] tagged )
        = i + i 1
    }
    ( shard_free chunks )
    ^ tids
}

// All chunk results present? (cluster job results are recorded by task-id.)
@ tids_ready * Swarm sw ( Vec i ) tids → b {
    : i n ( vec_len [i] tids )
    : ~ b all T : ~ i k 0
    ~ & all < k n {
        ? ! ( job_has # *JobNode . sw job ?? ( vec_get [i] tids k ) { T x → x F → 0 } ) { = all F } {}
        = k + k 1
    }
    ^ all
}

// Combine all chunk results with the reduce op (assumes ready). For a float
// task each partial is an f64 bit pattern: decode→f64, combine in f64, and
// return the combined f64 re-encoded as its bit pattern (the Task stores it
// that way; task_to_json reinterprets it for the model).
//
// Two result frames ride the wire: the expr kernel's legacy [partial:8], and
// the wasm kinds' [ok:1][partial:8]. A chunk whose ok=0 (module trap, missing
// runtime, GPU failure) is COUNTED, not folded — nfail>0 marks the task as
// failed instead of silently reducing zeros into the answer.
: Combined { i value i nfail }

@ tids_combine * Swarm sw i dtype i op ( Vec i ) tids → Combined {
    : i n ( vec_len [i] tids )
    : ~ i acc ? == dtype 1 ( f64_to_bits ( red_id_f op ) ) ( red_id op )
    : ~ i nfail 0
    : ~ i k 0
    ~ < k n {
        ?? ( job_await # *JobNode . sw job ?? ( vec_get [i] tids k ) { T x → x F → 0 } ) {
            T r → {
                ?? ( token_untag . sw key r ) {
                    T body → {
                        : ~ i ok 1
                        : ~ i off 0
                        ? >= ( vec_len [u] body ) 9 {
                            = ok ?? ( vec_get [u] body 0 ) { T x → # i x F → 0 }
                            = off 1
                        } {}
                        ? == ok 0 { = nfail + nfail 1 } {
                            : i raw ?? ( bytes_read_u64_be body off ) { T x → # i x F → 0 }
                            ? == dtype 1 {
                                = acc ( f64_to_bits ( red_combine_f op ( bits_to_f64 acc ) ( bits_to_f64 raw ) ) )
                            } {
                                = acc ( red_combine op acc raw )
                            }
                        }
                        ( vec_free [u] body )
                    }
                    F → { = nfail + nfail 1 }
                }
                ( vec_free [u] r )
            }
            F → { = nfail + nfail 1 }
        }
        = k + k 1
    }
    ^ @ Combined { acc nfail }
}

// Combine VECTOR results (sample / hist). Frame: [ok:1][count:4 BE][f64 LE ×
// count]. Sample chunks CONCATENATE in shard order (tids order = chunk order);
// hist chunks add ELEMENTWISE into K bins. A failed or malformed chunk counts
// toward nfail and contributes nothing.
: CombinedV { ( Vec u ) bytes i nfail }

// read/write one LE f64 (as its bit pattern) inside a byte vector
@ __f64le_get ( Vec u ) v i off → i { ^ ?? ( bytes_read_u64_le v off ) { T x → x F → 0 } }

@ __f64le_put ( Vec u ) v i off i bits → v {
    : ~ i k 0
    ~ < k 8 { ( vec_set [u] v + off k # u & >> bits * k 8 255 ) = k + k 1 }
}

@ tids_combine_vec * Swarm sw i mode i kbins ( Vec i ) tids → CombinedV {
    : b ksum | == mode ( gpu_mode_hist ) == mode ( gpu_mode_vecreduce )
    : ( Vec u ) acc ( vec_new [u] )
    ? ksum {
        : ~ i z 0
        ~ < z * kbins 8 { ( vec_push [u] acc 0 ) = z + z 1 }
    } {}
    : ~ i nfail 0
    : i n ( vec_len [i] tids )
    : ~ i k 0
    ~ < k n {
        ?? ( job_await # *JobNode . sw job ?? ( vec_get [i] tids k ) { T x → x F → 0 } ) {
            T r → {
                ?? ( token_untag . sw key r ) {
                    T body → {
                        : i ok ?? ( vec_get [u] body 0 ) { T x → # i x F → 0 }
                        : i cnt ?? ( bytes_read_u32_be body 1 ) { T x → # i x F → 0 }
                        : b sane == ( vec_len [u] body ) + 5 * cnt 8
                        ? & == ok 1 sane {
                            ? ksum {
                                ? == cnt kbins {
                                    : ~ i b 0
                                    ~ < b kbins {
                                        : f cur ( bits_to_f64 ( __f64le_get acc * b 8 ) )
                                        : f add ( bits_to_f64 ( __f64le_get body + 5 * b 8 ) )
                                        ( __f64le_put acc * b 8 ( f64_to_bits + cur add ) )
                                        = b + b 1
                                    }
                                } { = nfail + nfail 1 }
                            } {
                                : ( Vec u ) part ( bytes_slice body 5 ( vec_len [u] body ) )
                                ( vec_extend [u] acc part )
                                ( vec_free [u] part )
                            }
                        } { = nfail + nfail 1 }
                        ( vec_free [u] body )
                    }
                    F → { = nfail + nfail 1 }
                }
                ( vec_free [u] r )
            }
            F → { = nfail + nfail 1 }
        }
        = k + k 1
    }
    ^ @ CombinedV { acc nfail }
}

@ nchunks_for i nworkers → i { ^ ? > * nworkers 4 256 256 ? > nworkers 0 * nworkers 4 4 }

// ── submit role (manual CLI testing, no MCP) ─────────────────────

@ run_submit s host i port i op i lo i hi s expr s token → i {
    ?? ( relay_dial host port ) {
        T rc → {
            : i myid ( rand_u64 )
            : ( Vec u ) reg ( pk_from_id myid )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 250 )
            : *Swarm sw ( swarm_new rc myid ( role_client ) 0 token )
            ( swarm_join_group sw )
            ( swarm_discover sw 8 )
            : i nworkers ( roster_count # *Roster . sw roster )
            ? == nworkers 0 {
                ( nurl_print `swarm-mcp: no workers found\n` )
                ( swarm_free sw ) ( relay_close rc ) ^ 1
            } {}
            : ( Vec u ) eb ( bytes_from_str expr )
            : i nchunks ( nchunks_for nworkers )
            : ( Vec i ) tids ( cluster_submit sw op 0 lo hi eb nchunks )
            : ~ i rnd 0
            ~ & ! ( tids_ready sw tids ) < rnd 400 { ( swarm_pump sw 200 ) = rnd + rnd 1 }
            : Combined cb ( tids_combine sw 0 op tids )
            : i total . cb value
            ? > . cb nfail 0 { ( nurl_print `swarm-mcp: WARNING ` ) ( nurl_print_int . cb nfail ) ( nurl_print ` chunk(s) failed\n` ) } {}
            ( nurl_print ( reduce_op_name op ) ) ( nurl_print ` of (` ) ( nurl_print expr )
            ( nurl_print `) over [` ) ( nurl_print_int lo ) ( nurl_print `,` ) ( nurl_print_int hi )
            ( nurl_print `) = ` ) ( nurl_print_int total ) ( nurl_print `\n` )
            ( vec_free [i] tids ) ( vec_free [u] eb )
            ( swarm_free sw ) ( relay_close rc )
            ^ 0
        }
        F e → { ( nurl_print `swarm-mcp: submit could not dial relay\n` ) ^ 1 }
    }
}

// Chunk count for a wasm task: fewer chunks than the expression path (each
// chunk ships the module and spawns a wasmtime process), but enough to spread
// across the ring.
@ nchunks_wasm i nworkers → i { ^ ? > nworkers 0 * nworkers 2 2 }

// ── runwasm role (manual CLI testing of a compiled .wasm kernel) ──

@ run_runwasm s host i port i op i lo i hi s wasmpath s token → i {
    : !( Vec u ) IoErr wr ( read_file_bytes wasmpath )
    : ~ i rc 0
    ?? wr {
        F e → { ( nurl_print `swarm-mcp: cannot read wasm file\n` ) = rc 1 }
        T wasm → {
            ?? ( relay_dial host port ) {
                T relc → {
                    : i myid ( rand_u64 )
                    : ( Vec u ) reg ( pk_from_id myid )
                    ?? ( relay_register relc reg ) { T _ → {} F _ → {} }
                    ( vec_free [u] reg )
                    ( relay_set_timeout relc 250 )
                    : *Swarm sw ( swarm_new relc myid ( role_client ) 0 token )
                    ( swarm_join_group sw )
                    ( swarm_discover sw 8 )
                    : i nworkers ( roster_count # *Roster . sw roster )
                    ? == nworkers 0 {
                        ( nurl_print `swarm-mcp: no workers found\n` ) = rc 1
                        ( swarm_free sw ) ( relay_close relc )
                    } {
                        : i nchunks ( nchunks_wasm nworkers )
                        ( nurl_print `swarm-mcp: ` ) ( nurl_print_int nworkers ) ( nurl_print ` worker(s), ` )
                        ( nurl_print_int nchunks ) ( nurl_print ` wasm chunk(s)\n` )
                        : ( Vec i ) tids ( cluster_submit_wasm sw lo hi wasm nchunks ( kind_wasm ) )
                        : ~ i rnd 0
                        ~ & ! ( tids_ready sw tids ) < rnd 600 { ( swarm_pump sw 200 ) = rnd + rnd 1 }
                        : Combined cb ( tids_combine sw 0 op tids )
                        : i total . cb value
                        ? > . cb nfail 0 { ( nurl_print `swarm-mcp: WARNING ` ) ( nurl_print_int . cb nfail ) ( nurl_print ` chunk(s) failed\n` ) } {}
                        ( nurl_print ( reduce_op_name op ) ) ( nurl_print ` (wasm kernel) over [` )
                        ( nurl_print_int lo ) ( nurl_print `,` ) ( nurl_print_int hi )
                        ( nurl_print `) = ` ) ( nurl_print_int total ) ( nurl_print `\n` )
                        ( vec_free [i] tids )
                        ( swarm_free sw ) ( relay_close relc )
                    }
                }
                F e → { ( nurl_print `swarm-mcp: runwasm could not dial relay\n` ) = rc 1 }
            }
            ( vec_free [u] wasm )
        }
    }
    ^ rc
}

// ══════════════════════════════════════════════════════════════════
//  MCP server — the LLM-facing control surface
// ══════════════════════════════════════════════════════════════════

: Task {
    i id
    ( Vec u ) expr  // kernel bytes
    i dtype  // 0 int · 1 float (result holds an f64 bit pattern)
    i lo
    i hi
    i op
    i nchunks
    ( Vec i ) tids
    i done
    i result
    i failed  // chunks that reported ok=0 (task status "error" when > 0)
    i mode  // gpu_mode_scalar/sample/hist (scalar for every non-GPU task)
    i kbins  // histogram bin count (hist mode)
    ( Vec u ) vres  // vector result bytes (raw LE f64s; sample/hist modes)
    String out_file  // when set, the finished vector result is written here
    i dsid  // dataset id the task maps over (0 = none)
    i seeded  // dataset blocks seeded by THIS submit (0 = all were cached)
}

: McpState {
    s swarm  // *Swarm coordinator
    ( Vec s ) tasks  // *Task
    i next_id
    ( Vec s ) wcache  // *WasmCached — compiled kernel modules by source hash
    ( Vec s ) datasets  // *Dataset — uploaded data the CUDA tools map over
    i next_ds
    ( Vec String ) seeded  // "blockhex|chunk|epoch" — blocks CONFIRMED cached at their owner
}

// Constructor. The params share the field names (`lo`, `hi`, …); `= . t lo lo`
// is a field store — the field-store/local-shadow miscompile this used to work
// around was fixed in the compiler (NURL v0.10.4).
@ task_new i id ( Vec u ) expr i dtype i lo i hi i op i nchunks ( Vec i ) tids → *Task {
    : *Task t # *Task ( nurl_alloc Z Task )
    = . t id id
    = . t expr expr
    = . t dtype dtype
    = . t lo lo
    = . t hi hi
    = . t op op
    = . t nchunks nchunks
    = . t tids tids
    = . t done 0
    = . t result 0
    = . t failed 0
    = . t mode ( gpu_mode_scalar )
    = . t kbins 0
    = . t vres ( vec_new [u] )
    = . t out_file ( string_new )
    = . t dsid 0
    = . t seeded 0
    ^ t
}

: ~ i g_mcp 0

// ── datasets: uploaded arrays the CUDA tools map over ────────────
// A dataset is a flat f64 array held at the coordinator as raw LE bytes.
// Tasks reference it by id; sharding ships each chunk exactly its slice.

: Dataset { i id String name ( Vec u ) bytes ( Vec ( Vec u ) ) blocks }

@ ds_count_of * Dataset d → i { ^ / ( vec_len [u] . d bytes ) 8 }

@ ds_find i id → s {
    : *McpState st # *McpState g_mcp
    : i n ( vec_len [s] . st datasets )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . st datasets k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *Dataset d # *Dataset pp ? == . d id id { = found pp } {} } {}
        = k + k 1
    }
    ^ found
}

// one-pass min/max/mean of raw LE f64 bytes, attached to a JSON object
// Dataset-backed GPU submit over CONTENT-ADDRESSED blocks (payload v4).
// Chunking is block-aligned, so every 1 MiB block belongs to exactly one
// chunk; blocks not yet confirmed at their owner are seeded first as
// kind_blob tasks carrying the SAME ring key as the compute chunk (same
// ring + same key → same worker), and per-connection ordering guarantees
// the worker handles a seed before the compute that references it. A seed
// is recorded in `seeded` (hash|chunk|epoch) only after an OK result, so
// a lost seed re-seeds on the next submit instead of wedging.
// Dataset-backed GPU submit over CONTENT-ADDRESSED blocks (payload v4).
// Chunking is block-aligned, so every block belongs to exactly one chunk.
// Blocks not yet confirmed at their owner are seeded FIRST, strictly one at
// a time — submit a block, pump until its OK result, then the next. A single
// large frame is ever in flight to a given worker, which keeps the relay's
// forwarding stream from interleaving multi-frame bursts. Only after every
// referenced block is confirmed cached are the (small) compute chunks
// submitted; each references its blocks by hash and the worker assembles the
// slice from its cache, failing visibly on any missing block.
@ cluster_submit_wasm_gpu_ds * Swarm sw i mode i rlo i rhi i kbins ( Vec i ) params * Dataset d ( Vec u ) wasm i nchunks_want ( Vec String ) seeded * u nseed_cell → ( Vec i ) {
    : i bv ( blob_block_vals )
    : i blo / rlo bv
    : i bhi / + rhi - bv 1 bv
    : i nblocks - bhi blo
    : ~ i nc nchunks_want
    ? > nc nblocks { = nc nblocks } {}
    ? < nc 1 { = nc 1 } {}
    : ~ i nseeded 0
    // ── phase 1: seed every referenced block, serially + confirmed ──
    : ~ i i 0
    ~ < i nc {
        : i bs + blo / * i nblocks nc
        : i be + blo / * + i 1 nblocks nc
        : ( Vec u ) rkey ( chunk_key i )
        : ~ i b bs
        ~ < b be {
            : ( Vec u ) h ?? ( vec_get [( Vec u )] . d blocks b ) { T x → ( bytes_slice x 0 32 ) F → ( vec_new [u] ) }
            : String hex ( blob_hex h )
            : String sk ( string_from ( string_data hex ) )
            ( string_push_char sk 124 )
            ( string_push_int sk i )
            ( string_push_char sk 124 )
            ( string_push_int sk . sw epoch )
            : ~ b have F
            : i ns ( vec_len [String] seeded )
            : ~ i q 0
            ~ & ! have < q ns {
                ?? ( vec_get [String] seeded q ) { T e2 → { ? ( string_eq e2 sk ) { = have T } {} } F → {} }
                = q + q 1
            }
            ? have { ( string_free sk ) } {
                : i off * b * bv 8
                : i end0 + off * bv 8
                : i dn ( vec_len [u] . d bytes )
                : i end ? < end0 dn end0 dn
                : ( Vec u ) bb ( bytes_slice . d bytes off end )
                : ( Vec u ) sp ( blob_seed_payload h bb )
                : ( Vec u ) tg ( token_tag . sw key sp )
                : i stid ( job_submit # *JobNode . sw job ( kind_blob ) rkey tg )
                = nseeded + nseeded 1
                // confirm THIS block before sending the next
                : ~ i r 0
                ~ & < r 600 ! ( job_has # *JobNode . sw job stid ) { ( swarm_pump sw 100 ) = r + r 1 }
                : ~ b okseed F
                ?? ( job_await # *JobNode . sw job stid ) {
                    T rr → {
                        ?? ( token_untag . sw key rr ) {
                            T bd → { ? == ?? ( vec_get [u] bd 0 ) { T x → # i x F → 0 } 1 { = okseed T } {} ( vec_free [u] bd ) }
                            F → {}
                        }
                        ( vec_free [u] rr )
                    }
                    F → {}
                }
                ? okseed { ( vec_push [String] seeded sk ) } { ( string_free sk ) }
                ( vec_free [u] bb ) ( vec_free [u] sp ) ( vec_free [u] tg )
            }
            ( string_free hex ) ( vec_free [u] h )
            = b + b 1
        }
        ( vec_free [u] rkey )
        = i + i 1
    }
    // ── phase 2: submit the compute chunks (small, reference by hash) ──
    : ( Vec i ) tids ( vec_new [i] )
    = i 0
    ~ < i nc {
        : i bs + blo / * i nblocks nc
        : i be + blo / * + i 1 nblocks nc
        ? > be bs {
            : i clo0 * bs bv
            : i chi0 * be bv
            : i clo ? > rlo clo0 rlo clo0
            : i chi ? < rhi chi0 rhi chi0
            : ( Vec u ) rkey ( chunk_key i )
            : ( Vec ( Vec u ) ) hashes ( vec_new [( Vec u )] )
            : ~ i b bs
            ~ < b be {
                ?? ( vec_get [( Vec u )] . d blocks b ) { T x → { ( vec_push [( Vec u )] hashes ( bytes_slice x 0 32 ) ) } F → {} }
                = b + b 1
            }
            : ( Vec u ) payload ( wasm_gpu_chunk_payload_blobs mode clo chi kbins params bs hashes wasm )
            : ( Vec u ) tagged ( token_tag . sw key payload )
            ( vec_push [i] tids ( job_submit # *JobNode . sw job ( kind_wasm_gpu ) rkey tagged ) )
            ( blob_manifest_free hashes )
            ( vec_free [u] rkey ) ( vec_free [u] payload ) ( vec_free [u] tagged )
        } {}
        = i + i 1
    }
    ( nurl_poke nseed_cell 0 nseeded )
    ^ tids
}

@ __stats_json Json o ( Vec u ) bytes → v {
    : i cnt / ( vec_len [u] bytes ) 8
    ? == cnt 0 { ^ v } {}
    : ~ f mn ( bits_to_f64 ( __f64le_get bytes 0 ) )
    : ~ f mx mn
    : ~ f sum 0.0
    : ~ i k 0
    ~ < k cnt {
        : f v ( bits_to_f64 ( __f64le_get bytes * k 8 ) )
        ? < v mn { = mn v } {}
        ? > v mx { = mx v } {}
        = sum + sum v
        = k + k 1
    }
    ( json_obj_set o `min` ( json_float mn ) )
    ( json_obj_set o `max` ( json_float mx ) )
    ( json_obj_set o `mean` ( json_float / sum # f cnt ) )
}

// ── the coordinator's compiled-module cache ──────────────────────
// Keyed by the FNV hash of the GENERATED source: resubmitting the same kernel
// (a parameter scan, a new range, a re-run) skips the build API entirely —
// the module comes back in microseconds instead of a 5-15 s remote compile.
// Runtime params ride argv, so they never perturb the hash.

: WasmCached { String hash ( Vec u ) wasm }

@ __wcache_max → i { ^ 32 }

@ __wcache_get s hex → ?( Vec u ) {
    : *McpState st # *McpState g_mcp
    : i n ( vec_len [s] . st wcache )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . st wcache k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *WasmCached wc # *WasmCached pp
            ? != 0 ( nurl_str_eq ( string_data . wc hash ) hex ) { = found pp } {}
        } {}
        = k + k 1
    }
    ? == # i found 0 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : *WasmCached wc # *WasmCached found
    : ( Vec u ) cp ( vec_with_cap [u] ( vec_len [u] . wc wasm ) )
    ( vec_extend [u] cp . wc wasm )
    ^ @ ?( Vec u ) { T cp }
}

// Insert a copy. At capacity the whole cache resets — a parameter scan lives
// in one entry, so simplicity beats an eviction policy here.
@ __wcache_put s hex ( Vec u ) wasm → v {
    : *McpState st # *McpState g_mcp
    ? >= ( vec_len [s] . st wcache ) ( __wcache_max ) {
        : i n ( vec_len [s] . st wcache )
        : ~ i k 0
        ~ < k n {
            : s pp ?? ( vec_get [s] . st wcache k ) { T x → x F → # s 0 }
            ? != # i pp 0 {
                : *WasmCached wc # *WasmCached pp
                ( string_free . wc hash ) ( vec_free [u] . wc wasm )
                ( nurl_free pp )
            } {}
            = k + k 1
        }
        ( vec_free [s] . st wcache )
        = . st wcache ( vec_new [s] )
    } {}
    : *WasmCached wc # *WasmCached ( nurl_alloc Z WasmCached )
    = . wc hash ( string_from hex )
    : ( Vec u ) cp ( vec_with_cap [u] ( vec_len [u] wasm ) )
    ( vec_extend [u] cp wasm )
    = . wc wasm cp
    ( vec_push [s] . st wcache # s wc )
}

@ mcp_swarm → *Swarm { : *McpState st # *McpState g_mcp ^ # *Swarm . st swarm }

@ mcp_pump i rounds → v {
    : *Swarm sw ( mcp_swarm )
    : ~ i k 0
    ~ < k rounds { ( swarm_pump sw 150 ) = k + k 1 }
}

// Refresh one task's status; combine if every chunk has landed. A finished
// vector task with an out_file writes the raw LE f64s there (once).
@ task_refresh * Task t → v {
    ? == . t done 1 { ^ v } {}
    : *Swarm sw ( mcp_swarm )
    ? ( tids_ready sw . t tids ) {
        ? == . t mode ( gpu_mode_scalar ) {
            : Combined cb ( tids_combine sw . t dtype . t op . t tids )
            = . t result . cb value
            = . t failed . cb nfail
        } {
            : CombinedV cv ( tids_combine_vec sw . t mode . t kbins . t tids )
            ( vec_free [u] . t vres )
            = . t vres . cv bytes
            = . t failed . cv nfail
            ? & == . t failed 0 > ( string_len . t out_file ) 0 {
                ?? ( write_file_bytes ( string_data . t out_file ) . t vres ) {
                    T _ → {}
                    F e → { = . t failed 1 }
                }
            } {}
        }
        = . t done 1
    } {}
}

@ task_find i id → s {
    : *McpState st # *McpState g_mcp
    : i n ( vec_len [s] . st tasks )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . st tasks k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *Task t # *Task pp ? == . t id id { = found pp } {} } {}
        = k + k 1
    }
    ^ found
}

// Build the JSON-as-text result body for one task (LLM-readable + parseable).
@ task_to_json * Task t → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `task_id` ( json_int . t id ) )
    ( json_obj_set o `status` ( json_str_lit ? == . t done 1 ? > . t failed 0 `error` `done` `running` ) )
    ? > . t failed 0 { ( json_obj_set o `failed_chunks` ( json_int . t failed ) ) } {}
    : String es ( bytes_to_str . t expr )
    ( json_obj_set o `kernel` ( json_str_lit ( string_data es ) ) )
    ( string_free es )
    ( json_obj_set o `reduce` ( json_str_lit ( reduce_op_name . t op ) ) )
    ( json_obj_set o `dtype` ( json_str_lit ? == . t dtype 1 `float` `int` ) )
    ( json_obj_set o `lo` ( json_int . t lo ) )
    ( json_obj_set o `hi` ( json_int . t hi ) )
    ( json_obj_set o `chunks` ( json_int . t nchunks ) )
    ? != . t dsid 0 {
        ( json_obj_set o `dataset` ( json_int . t dsid ) )
        // how many 1 MiB blocks this submit actually shipped — 0 means the
        // workers already held every block (re-submit / next round is free)
        ( json_obj_set o `seeded_blocks` ( json_int . t seeded ) )
    } {}
    ? & == . t done 1 == . t failed 0 {
        ? == . t mode ( gpu_mode_scalar ) {
            ? == . t dtype 1 { ( json_obj_set o `result` ( json_float ( bits_to_f64 . t result ) ) ) }
            { ( json_obj_set o `result` ( json_int . t result ) ) }
        } {
            ( __task_vres_json o t )
        }
    } {}
    ^ o
}

// Attach a finished vector result: always count + min/max/mean stats; the
// values themselves inline as a JSON array when small, as base64 (raw
// little-endian f64s) when moderate, and only in out_file beyond that —
// an MCP text result must stay readable by a language model.
@ __vres_json_max → i { ^ 1024 }

@ __vres_b64_max → i { ^ 65536 }

@ __task_vres_json Json o * Task t → v {
    : i cnt / ( vec_len [u] . t vres ) 8
    ( json_obj_set o `count` ( json_int cnt ) )
    ? > ( string_len . t out_file ) 0 {
        ( json_obj_set o `saved_to` ( json_str_lit ( string_data . t out_file ) ) )
    } {}
    ? == cnt 0 { ^ v } {}
    // stats in one pass
    : ~ f mn ( bits_to_f64 ( __f64le_get . t vres 0 ) )
    : ~ f mx mn
    : ~ f sum 0.0
    : ~ i k 0
    ~ < k cnt {
        : f v ( bits_to_f64 ( __f64le_get . t vres * k 8 ) )
        ? < v mn { = mn v } {}
        ? > v mx { = mx v } {}
        = sum + sum v
        = k + k 1
    }
    ( json_obj_set o `min` ( json_float mn ) )
    ( json_obj_set o `max` ( json_float mx ) )
    ( json_obj_set o `mean` ( json_float / sum # f cnt ) )
    ? <= cnt ( __vres_json_max ) {
        : Json arr ( json_arr_new )
        : ~ i j 0
        ~ < j cnt { ( json_arr_push arr ( json_float ( bits_to_f64 ( __f64le_get . t vres * j 8 ) ) ) ) = j + j 1 }
        ( json_obj_set o `values` arr )
    } {
        ? <= cnt ( __vres_b64_max ) {
            : String b64 ( b64_encode_vec . t vres )
            ( json_obj_set o `values_base64_f64le` ( json_str_lit ( string_data b64 ) ) )
            ( string_free b64 )
        } {}
    }
}

@ tool_result_json Json o → Json {
    : String s ( json_stringify o )
    : Json r ( mcp_tool_result_text ( string_data s ) )
    ( string_free s )
    ( json_free o )
    ^ r
}

// ── tool: compute_submit ─────────────────────────────────────────

@ tool_submit Json args → Json {
    : ?Json ej ( json_obj_get args `expr` )
    : ?Json lj ( json_obj_get args `lo` )
    : ?Json hj ( json_obj_get args `hi` )
    ? | ! ?? ej { T _ → T F → F } | ! ?? lj { T _ → T F → F } ! ?? hj { T _ → T F → F } {
        ^ ( mcp_tool_result_error `compute_submit needs "expr" (string), "lo" (int), "hi" (int); "reduce" optional` )
    } {}
    : s expr ?? ej { T v → ( json_str_data v ) F → `` }
    : i lo ?? lj { T v → ( json_as_int v ) F → 0 }
    : i hi ?? hj { T v → ( json_as_int v ) F → 0 }
    : i op ?? ( json_obj_get args `reduce` ) { T v → ( reduce_op_of ( json_str_data v ) 0 ) F → 0 }
    : i dtype ?? ( json_obj_get args `dtype` ) { T v → ? != 0 ( nurl_str_eq ( json_str_data v ) `float` ) 1 0 F → 0 }
    ? >= lo hi { ^ ( mcp_tool_result_error `empty range: need lo < hi` ) } {}

    // Validate the kernel parses before shipping it to workers.
    : ( Vec u ) eb ( bytes_from_str expr )
    : *EParser ep # *EParser ( nurl_alloc Z EParser )
    : i root ( expr_parse eb ep )
    : b okp . ep ok
    ( eparser_free ep )
    ? ! okp {
        ( vec_free [u] eb )
        ^ ( mcp_tool_result_error `could not parse kernel — operators: + - * / % < <= > >= == != & | ?: ; functions: min max abs ; variable: x` )
    } {}

    // Discover the live workers, then shard + submit.
    // a dead relay here means the coordinator reconnects to the next in the
    // list before submitting — a relay failure does not take the API down
    ? ( mcp_ensure_relay ) {} {}
    : *Swarm sw ( mcp_swarm )
    ( swarm_discover sw 6 )
    : i nworkers ( roster_count # *Roster . sw roster )
    ? == nworkers 0 {
        ( vec_free [u] eb )
        ^ ( mcp_tool_result_error `no workers in the cluster — start some with 'swarm-mcp worker'` )
    } {}
    : i nchunks ( nchunks_for nworkers )
    : ( Vec i ) tids ( cluster_submit sw op dtype lo hi eb nchunks )

    : *McpState st # *McpState g_mcp
    : *Task t ( task_new . st next_id eb dtype lo hi op nchunks tids )
    = . st next_id + . st next_id 1
    ( vec_push [s] . st tasks # s t )

    // Pump briefly so small tasks come back as "done" immediately.
    ( mcp_pump 8 )
    ( task_refresh t )
    ^ ( tool_result_json ( task_to_json t ) )
}

// ── tool: compute_run_wasm / compute_submit_kernel (phase 2) ─────────
// Ship a compiled wasm module to the cluster as a task (takes ownership of
// `wasm`, frees it). Shared by both phase-2 tools.

@ __ship_wasm ( Vec u ) wasm i lo i hi i op i dtype i gpu → Json {
    ? == ( vec_len [u] wasm ) 0 { ( vec_free [u] wasm ) ^ ( mcp_tool_result_error `empty wasm module` ) } {}
    // a dead relay here means the coordinator reconnects to the next in the
    // list before submitting — a relay failure does not take the API down
    ? ( mcp_ensure_relay ) {} {}
    : *Swarm sw ( mcp_swarm )
    ( swarm_discover sw 6 )
    : i nworkers ? != gpu 0
    ( roster_count_caps # *Roster . sw roster ( cap_gpu ) )
    ( roster_count # *Roster . sw roster )
    ? == nworkers 0 {
        ( vec_free [u] wasm )
        ^ ? != gpu 0
        ( mcp_tool_result_error `no GPU workers in the cluster — start some with 'swarm-mcp --worker --gpu' (needs the pure-NURL wasmtime and an NVIDIA GPU)` )
        ( mcp_tool_result_error `no workers in the cluster — start some with 'swarm-mcp worker'` )
    } {}
    : i nchunks ( nchunks_wasm nworkers )
    : i kind ? != gpu 0 ( kind_wasm_gpu ) ( kind_wasm )
    : ( Vec i ) tids ( cluster_submit_wasm sw lo hi wasm nchunks kind )
    ( vec_free [u] wasm )
    : *McpState st # *McpState g_mcp
    : *Task t ( task_new . st next_id ( bytes_from_str ? != gpu 0 `<wasm kernel (gpu)>` `<wasm kernel>` ) dtype lo hi op nchunks tids )
    = . st next_id + . st next_id 1
    ( vec_push [s] . st tasks # s t )
    ( mcp_pump 8 )
    ( task_refresh t )
    ^ ( tool_result_json ( task_to_json t ) )
}

@ tool_run_wasm Json args → Json {
    : ?Json wj ( json_obj_get args `wasm_base64` )
    : ?Json lj ( json_obj_get args `lo` )
    : ?Json hj ( json_obj_get args `hi` )
    ? | ! ?? wj { T _ → T F → F } | ! ?? lj { T _ → T F → F } ! ?? hj { T _ → T F → F } {
        ^ ( mcp_tool_result_error `compute_run_wasm needs "wasm_base64" (string), "lo" (int), "hi" (int); "reduce" optional` )
    } {}
    : s w64 ?? wj { T v → ( json_str_data v ) F → `` }
    : i lo ?? lj { T v → ( json_as_int v ) F → 0 }
    : i hi ?? hj { T v → ( json_as_int v ) F → 0 }
    : i op ?? ( json_obj_get args `reduce` ) { T v → ( reduce_op_of ( json_str_data v ) 0 ) F → 0 }
    : i dtype ?? ( json_obj_get args `dtype` ) { T v → ? != 0 ( nurl_str_eq ( json_str_data v ) `float` ) 1 0 F → 0 }
    ? >= lo hi { ^ ( mcp_tool_result_error `empty range: need lo < hi` ) } {}
    : i gpu ?? ( json_obj_get args `gpu` ) { T v → ? ( json_as_bool v ) 1 0 F → 0 }
    : !( Vec u ) ParseErr dr ( b64_decode_vec w64 )
    ?? dr {
        F e → { ^ ( mcp_tool_result_error `wasm_base64 is not valid base64` ) }
        T wasm → { ^ ( __ship_wasm wasm lo hi op dtype gpu ) }
    }
}

// compute_submit_kernel: the server compiles NURL source → wasm itself (via the
// build API), then runs it — the model hands over a kernel as plain NURL.
@ tool_submit_kernel Json args → Json {
    : ?Json sj ( json_obj_get args `source` )
    : ?Json lj ( json_obj_get args `lo` )
    : ?Json hj ( json_obj_get args `hi` )
    ? | ! ?? sj { T _ → T F → F } | ! ?? lj { T _ → T F → F } ! ?? hj { T _ → T F → F } {
        ^ ( mcp_tool_result_error `compute_submit_kernel needs "source" (NURL program), "lo" (int), "hi" (int); "reduce" optional` )
    } {}
    : s source ?? sj { T v → ( json_str_data v ) F → `` }
    : i lo ?? lj { T v → ( json_as_int v ) F → 0 }
    : i hi ?? hj { T v → ( json_as_int v ) F → 0 }
    : i op ?? ( json_obj_get args `reduce` ) { T v → ( reduce_op_of ( json_str_data v ) 0 ) F → 0 }
    : i dtype ?? ( json_obj_get args `dtype` ) { T v → ? != 0 ( nurl_str_eq ( json_str_data v ) `float` ) 1 0 F → 0 }
    : i gpu ?? ( json_obj_get args `gpu` ) { T v → ? ( json_as_bool v ) 1 0 F → 0 }
    : i kkind ?? ( json_obj_get args `kind` ) { T v → ? != 0 ( nurl_str_eq ( json_str_data v ) `chunk` ) 1 0 F → 0 }
    ? >= lo hi { ^ ( mcp_tool_result_error `empty range: need lo < hi` ) } {}
    // Wrap the bare kernel (`@ kernel i x → i`, or `→ f` for dtype "float"; with
    // kind "chunk", `@ kernel i lo i hi → i/f` called once per chunk) into a
    // full program: a main that reads lo/hi from argv and prints the partial
    // (an f64 bit pattern in float).
    : String wrapped ( wrap_kernel source op dtype kkind )
    : !( Vec u ) String cr ( compile_to_wasm ( string_data wrapped ) )
    ( string_free wrapped )
    ?? cr {
        F msg → {
            : String em ( string_concat ( string_from `kernel did not compile: ` ) msg )
            : Json e ( mcp_tool_result_error ( string_data em ) )
            ( string_free em ) ( string_free msg )
            ^ e
        }
        T wasm → { ^ ( __ship_wasm wasm lo hi op dtype gpu ) }
    }
}

// ── the CUDA tool family (scalar reduce / sample / histogram) ────
// The model hands over ONLY CUDA-C device functions; the server generates the
// whole GPU chunk-kernel program around them (cudakernel.nu), compiles it to
// wasm — through the coordinator's module cache, so a repeat submit (a
// parameter scan, a new range) skips the build API — and ships it to the GPU
// capability domain. Results combine in f64.

// "params" (JSON array of numbers) → their f64 bit patterns. Missing key →
// empty vec (T); a present-but-malformed value → F.
@ __parse_params Json args → ?( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : ?Json pj ( json_obj_get args `params` )
    : ~ b ok T
    ?? pj {
        F → {}
        T arr → {
            : i n ( json_arr_len arr )
            : ~ i k 0
            ~ & ok < k n {
                ?? ( json_arr_get arr k ) {
                    T el → {
                        ?? ( json_num_as_f el ) {
                            T fv → { ( vec_push [i] out ( f64_to_bits fv ) ) }
                            F → { = ok F }
                        }
                    }
                    F → { = ok F }
                }
                = k + k 1
            }
        }
    }
    ? ! ok { ( vec_free [i] out ) ^ @ ?( Vec i ) { F # ( Vec i ) 0 } } {}
    ^ @ ?( Vec i ) { T out }
}

// Shared CUDA submit: validate → wrap → cached-or-remote compile → shard to
// the GPU ring → record the task. Frees `params`; borrows `cuda`/`out_file`.
@ __submit_cuda_task s cuda i op i mode i lo i hi i kbins ( Vec i ) params s out_file i dsid → Json {
    ? ! ( cuda_src_ok cuda ) {
        ( vec_free [i] params )
        ^ ( mcp_tool_result_error `the CUDA source may not contain a backtick character` )
    } {}
    : s entry ? == mode ( gpu_mode_hist ) `long long bin` `double f`
    ? < ( nurl_str_find cuda entry ) 0 {
        ( vec_free [i] params )
        ^ ? == mode ( gpu_mode_hist )
        ( mcp_tool_result_error `the CUDA source must define __device__ long long bin(long long x) { ... } (and may define __device__ double val(long long x); with a dataset both take (long long x, double v); with params, a trailing const double* p)` )
        ( mcp_tool_result_error `the CUDA source must define __device__ double f(long long x) { ... } (with a dataset: f(long long x, double v); with params, a trailing const double* p; helpers are fine, f is the entry the generated kernel calls)` )
    } {}
    // resolved range (a dataset defaults a missing lo/hi to [0, count))
    : ~ i rlo lo
    : ~ i rhi hi
    // dataset: bind it, default a missing range to [0, count), bounds-check
    : ~ s dsp # s 0
    ? != dsid 0 {
        = dsp ( ds_find dsid )
        ? == # i dsp 0 {
            ( vec_free [i] params )
            ^ ( mcp_tool_result_error `no such dataset — upload one with compute_upload_data (or check compute_list_data)` )
        } {}
        : *Dataset d # *Dataset dsp
        ? < rlo 0 { = rlo 0 } {}
        ? < rhi 0 { = rhi ( ds_count_of d ) } {}
        ? | | < rlo 0 > rhi ( ds_count_of d ) >= rlo rhi {
            ( vec_free [i] params )
            ^ ( mcp_tool_result_error `the range [lo, hi) must lie within the dataset: 0 <= lo < hi <= its count` )
        } {}
    } {
        ? | < rlo 0 < rhi 0 {
            ( vec_free [i] params )
            ^ ( mcp_tool_result_error `"lo" and "hi" are required without a "dataset"` )
        } {}
        ? >= rlo rhi {
            ( vec_free [i] params )
            ^ ( mcp_tool_result_error `empty range: need lo < hi` )
        } {}
    }
    // sample-mode result caps depend on the resolved span
    ? == mode ( gpu_mode_sample ) {
        : i span0 - rhi rlo
        ? > span0 1048576 {
            ( vec_free [i] params )
            ^ ( mcp_tool_result_error `sample range too large: hi - lo must be <= 1048576 (use compute_submit_cuda to reduce, or compute_histogram_cuda to bin)` )
        } {}
        ? & > span0 ( __vres_b64_max ) == ( nurl_str_len out_file ) 0 {
            ( vec_free [i] params )
            ^ ( mcp_tool_result_error `a sample larger than 65536 values needs "out_file" (an absolute path on the MCP host) — the values cannot ride a text result` )
        } {}
    } {}
    : i has_params ? > ( vec_len [i] params ) 0 1 0
    : i has_data ? != dsid 0 1 0
    : String wrapped ( cuda_wrap cuda op mode has_params has_data )
    // module cache: keyed by the generated source (params ride argv → the
    // hash — and the worker-side module cache — survive parameter changes)
    : ( Vec u ) srcb ( bytes_from_str ( string_data wrapped ) )
    : String hex ( _wasm_hash srcb )
    ( vec_free [u] srcb )
    : ~ ( Vec u ) wasm ( vec_new [u] )
    : ~ b have F
    ?? ( __wcache_get ( string_data hex ) ) {
        T hitw → { ( vec_free [u] wasm ) = wasm hitw = have T }
        F → {}
    }
    ? ! have {
        : !( Vec u ) String cr ( compile_to_wasm ( string_data wrapped ) )
        ?? cr {
            F msg → {
                : String em ( string_concat ( string_from `CUDA kernel program did not compile: ` ) msg )
                : Json e ( mcp_tool_result_error ( string_data em ) )
                ( string_free em ) ( string_free msg )
                ( string_free wrapped ) ( string_free hex ) ( vec_free [i] params ) ( vec_free [u] wasm )
                ^ e
            }
            T builtw → {
                ( vec_free [u] wasm )
                = wasm builtw
                ( __wcache_put ( string_data hex ) wasm )
            }
        }
    } {}
    ( string_free wrapped ) ( string_free hex )
    // a dead relay here means the coordinator reconnects to the next in the
    // list before submitting — a relay failure does not take the API down
    ? ( mcp_ensure_relay ) {} {}
    : *Swarm sw ( mcp_swarm )
    ( swarm_discover sw 6 )
    : i ngpu ( roster_count_caps # *Roster . sw roster ( cap_gpu ) )
    ? == ngpu 0 {
        ( vec_free [i] params ) ( vec_free [u] wasm )
        ^ ( mcp_tool_result_error `no GPU workers in the cluster — start some with 'swarm-mcp --worker --gpu' (needs the pure-NURL wasmtime and an NVIDIA GPU)` )
    } {}
    // chunk count: spread over the GPU workers; never shard an empty range.
    // With a dataset the split is BLOCK-ALIGNED inside the v4 submit — the
    // 12 MiB slice-per-frame budget is gone, blocks (1 MiB) travel once.
    : i nchunks0 ( nchunks_wasm ngpu )
    : i span - rhi rlo
    : ~ i nchunks nchunks0
    ? > nchunks span { = nchunks span } {}
    : *McpState st0 # *McpState g_mcp
    : *u nseed ( nurl_alloc 8 )
    ( nurl_poke nseed 0 0 )
    : ~ ( Vec i ) tids ( vec_new [i] )
    ? != dsid 0 {
        : *Dataset d # *Dataset dsp
        ( vec_free [i] tids )
        = tids ( cluster_submit_wasm_gpu_ds sw mode rlo rhi kbins params d wasm nchunks . st0 seeded nseed )
    } {
        : ( Vec u ) dbytes ( vec_new [u] )
        ( vec_free [i] tids )
        = tids ( cluster_submit_wasm_gpu sw mode rlo rhi kbins params dbytes wasm nchunks )
        ( vec_free [u] dbytes )
    }
    = nchunks ( vec_len [i] tids )
    ( vec_free [i] params ) ( vec_free [u] wasm )
    : *McpState st # *McpState g_mcp
    : *Task t ( task_new . st next_id ( bytes_from_str cuda ) 1 rlo rhi op nchunks tids )
    = . t mode mode
    = . t kbins kbins
    = . t dsid dsid
    = . t seeded ( nurl_peek nseed 0 )
    ( nurl_free nseed )
    ? > ( nurl_str_len out_file ) 0 { ( string_push_str . t out_file out_file ) } {}
    = . st next_id + . st next_id 1
    ( vec_push [s] . st tasks # s t )
    ( mcp_pump 8 )
    ( task_refresh t )
    ^ ( tool_result_json ( task_to_json t ) )
}

// Parse a JSON number array into a fresh Vec f (F on any non-number).
@ __parse_farr Json arr ( Vec f ) out → b {
    : i n ( json_arr_len arr )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        ?? ( json_arr_get arr k ) {
            T el → { ?? ( json_num_as_f el ) { T fv → { ( vec_push [f] out fv ) } F → { = ok F } } }
            F → { = ok F }
        }
        = k + k 1
    }
    ^ ok
}

// ── the iteration engine: compute_iterate ────────────────────────
// One vecreduce round: submit the module over [rlo,rhi) with `state` as the
// runtime params, pump to completion, and combine the per-chunk K-vectors
// into the summed gradient `grad` (K floats). Returns the failed-chunk count
// (0 = every chunk reported). The dataset path (dsid != 0) references cached
// blocks by hash, so after the first round a round ships only the state.
// One accumulate round: submit the vecreduce module over [rlo,rhi) with the
// current `state` (S floats) plus any user `xparams` as the runtime params, and
// combine the per-chunk A-vectors into the summed accumulator `grad` (A floats).
// The accumulator dimension A is decoupled from the state length S — the
// gradient of a fit and the state it updates coincide, but k-means sufficient
// statistics, EM stats and A·v for power iteration do not. Returns the
// failed-chunk count (0 = every chunk reported).
@ __iterate_round * Swarm sw ( Vec u ) wasm i S i A ( Vec i ) xparams i rlo i rhi ( Vec f ) state i dsid ( Vec String ) seeded * u nseed_cell ( Vec f ) grad → i {
    : ( Vec i ) params ( vec_new [i] )
    : ~ i j 0
    ~ < j S { ( vec_push [i] params ( f64_to_bits ?? ( vec_get [f] state j ) { T x → x F → 0.0 } ) ) = j + j 1 }
    : ~ i xj 0
    ~ < xj ( vec_len [i] xparams ) { ( vec_push [i] params ?? ( vec_get [i] xparams xj ) { T x → x F → 0 } ) = xj + xj 1 }
    : *McpState st0 # *McpState g_mcp
    : i ngpu ( roster_count_caps # *Roster . sw roster ( cap_gpu ) )
    : i nchunks0 ( nchunks_wasm ngpu )
    : i span - rhi rlo
    : ~ i nchunks nchunks0
    ? > nchunks span { = nchunks span } {}
    : ~ ( Vec i ) tids ( vec_new [i] )
    ? != dsid 0 {
        : *Dataset d # *Dataset ( ds_find dsid )
        ( vec_free [i] tids )
        = tids ( cluster_submit_wasm_gpu_ds sw ( gpu_mode_vecreduce ) rlo rhi A params d wasm nchunks . st0 seeded nseed_cell )
    } {
        : ( Vec u ) dbytes ( vec_new [u] )
        ( vec_free [i] tids )
        = tids ( cluster_submit_wasm_gpu sw ( gpu_mode_vecreduce ) rlo rhi A params dbytes wasm nchunks )
        ( vec_free [u] dbytes )
    }
    ( vec_free [i] params )
    // drive to completion
    : ~ i r 0
    ~ & < r 4000 ! ( tids_ready sw tids ) { ( swarm_pump sw 100 ) = r + r 1 }
    : CombinedV cv ( tids_combine_vec sw ( gpu_mode_vecreduce ) A tids )
    ( vec_free [i] tids )
    ( vec_clear [f] grad )
    : ~ i b 0
    ~ < b A { ( vec_push [f] grad ( bits_to_f64 ( __f64le_get . cv bytes * b 8 ) ) ) = b + b 1 }
    ( vec_free [u] . cv bytes )
    ^ . cv nfail
}

// One update round: run the model's update() as a sample over [0, S) on a GPU
// worker, gather the S new state components, and overwrite `state` in place.
// The packed param buffer the update kernel reads is state ++ acc ++ [N] ++
// xparams. Returns the failed-chunk count (0 = the whole state came back).
@ __iterate_update * Swarm sw ( Vec u ) uwasm i S i A ( Vec f ) grad i N ( Vec i ) xparams ( Vec f ) state → i {
    : ( Vec i ) up ( vec_new [i] )
    : ~ i j 0
    ~ < j S { ( vec_push [i] up ( f64_to_bits ?? ( vec_get [f] state j ) { T x → x F → 0.0 } ) ) = j + j 1 }
    : ~ i a 0
    ~ < a A { ( vec_push [i] up ( f64_to_bits ?? ( vec_get [f] grad a ) { T x → x F → 0.0 } ) ) = a + a 1 }
    ( vec_push [i] up ( f64_to_bits # f N ) )
    : ~ i xj 0
    ~ < xj ( vec_len [i] xparams ) { ( vec_push [i] up ?? ( vec_get [i] xparams xj ) { T x → x F → 0 } ) = xj + xj 1 }
    : ( Vec u ) nodata ( vec_new [u] )
    : ( Vec i ) tids ( cluster_submit_wasm_gpu sw ( gpu_mode_sample ) 0 S 0 up nodata uwasm 1 )
    ( vec_free [i] up ) ( vec_free [u] nodata )
    : ~ i r 0
    ~ & < r 4000 ! ( tids_ready sw tids ) { ( swarm_pump sw 100 ) = r + r 1 }
    : CombinedV cv ( tids_combine_vec sw ( gpu_mode_sample ) 0 tids )
    ( vec_free [i] tids )
    ? == . cv nfail 0 {
        ? == ( vec_len [u] . cv bytes ) * S 8 {
            : ~ i b 0
            ~ < b S { ( vec_set [f] state b ( bits_to_f64 ( __f64le_get . cv bytes * b 8 ) ) ) = b + b 1 }
        } {}
    } {}
    : i nf . cv nfail
    ( vec_free [u] . cv bytes )
    ^ nf
}

@ tool_iterate Json args → Json {
    : ?Json cj ( json_obj_get args `cuda` )
    : ?Json sj ( json_obj_get args `state` )
    : ?Json uj ( json_obj_get args `update` )
    : b have_cuda ?? cj { T _ → T F → F }
    : b have_state ?? sj { T _ → T F → F }
    : b have_update ?? uj { T _ → T F → F }
    ? & have_cuda have_state {} {
        ^ ( mcp_tool_result_error `compute_iterate needs "cuda" (a __device__ void grad(long long x[, double v], double* g[, const double* p]) that scatter-adds via swarm_g_add(g, j, val)), "state" (the initial parameter vector), and "rounds". Default (SGD) mode also needs "lr"; general mode instead takes an "update" device function (and optional "acc_dim"). "dataset" or "lo"/"hi", "params" and "epsilon" optional` )
    }
    : s cuda ?? cj { T x → ( json_str_data x ) F → `` }
    : s upd ?? uj { T x → ( json_str_data x ) F → `` }
    : ( Vec f ) state ( vec_new [f] )
    : ~ b spok F
    ?? sj { T arr → { ? ( json_is_arr arr ) { = spok ( __parse_farr arr state ) } {} } F → {} }
    ? & spok > ( vec_len [f] state ) 0 {} {
        ( vec_free [f] state )
        ^ ( mcp_tool_result_error `"state" must be a non-empty array of numbers — the parameter vector that iterates and is returned` )
    }
    : i S ( vec_len [f] state )
    ? > S 4096 { ( vec_free [f] state ) ^ ( mcp_tool_result_error `"state" is limited to 4096 components` ) } {}
    // accumulator dimension: defaults to the state length (a fit's gradient),
    // but the reduction that feeds the update can be wider (k-means sufficient
    // statistics, EM stats, A·v) — decouple it with "acc_dim".
    : i A ?? ( json_obj_get args `acc_dim` ) { T x → ?? ( json_num_as_i x ) { T v → v F → S } F → S }
    ? & > A 0 <= A 65536 {} { ( vec_free [f] state ) ^ ( mcp_tool_result_error `"acc_dim" must be between 1 and 65536 (the accumulator dimension your grad scatters into)` ) }
    ? & ! have_update != A S { ( vec_free [f] state ) ^ ( mcp_tool_result_error `default (SGD) mode requires "acc_dim" == the state length; to reduce into a wider accumulator provide an "update" device function` ) } {}
    // runtime params (constant across rounds), packed as f64 bits — grad reads
    // them at p[S..], update via swarm_param(i)
    : ( Vec i ) xparams ( vec_new [i] )
    ?? ( json_obj_get args `params` ) { T pj → { ? ( json_is_arr pj ) {
                : ( Vec f ) pf ( vec_new [f] )
                ? ( __parse_farr pj pf ) {
                    : ~ i pk 0
                    ~ < pk ( vec_len [f] pf ) { ( vec_push [i] xparams ( f64_to_bits ?? ( vec_get [f] pf pk ) { T x → x F → 0.0 } ) ) = pk + pk 1 }
                } {}
                ( vec_free [f] pf )
            } {} } F → {} }
    : i rounds ?? ( json_obj_get args `rounds` ) { T x → ?? ( json_num_as_i x ) { T v → v F → 0 } F → 0 }
    ? & > rounds 0 <= rounds 100000 {} { ( vec_free [f] state ) ( vec_free [i] xparams ) ^ ( mcp_tool_result_error `"rounds" must be between 1 and 100000` ) }
    : f lr ?? ( json_obj_get args `lr` ) { T x → ?? ( json_num_as_f x ) { T v → v F → 0.0 } F → 0.0 }
    ? & ! have_update == lr 0.0 { ( vec_free [f] state ) ( vec_free [i] xparams ) ^ ( mcp_tool_result_error `default (SGD) mode requires "lr" (learning rate) — non-zero — or provide an "update" device function for a custom step rule` ) } {}
    : f eps ?? ( json_obj_get args `epsilon` ) { T x → ?? ( json_num_as_f x ) { T v → v F → 0.0 } F → 0.0 }
    : i dsid ?? ( json_obj_get args `dataset` ) { T x → ?? ( json_num_as_i x ) { T v → v F → 0 } F → 0 }
    // validate the grad entry + backtick-free source
    ? ! ( cuda_src_ok cuda ) { ( vec_free [f] state ) ( vec_free [i] xparams ) ^ ( mcp_tool_result_error `the CUDA source may not contain a backtick character` ) } {}
    ? >= ( nurl_str_find cuda `void grad` ) 0 {} {
        ( vec_free [f] state ) ( vec_free [i] xparams )
        ^ ( mcp_tool_result_error `the CUDA source must define __device__ void grad(long long x[, double v], double* g[, const double* p]) and scatter-add the accumulator with swarm_g_add(g, j, val) — with a dataset grad also takes double v = data[x]; p[0..state] is the current state, p[state..] your "params"` )
    }
    ? have_update {
        ? ! ( cuda_src_ok upd ) { ( vec_free [f] state ) ( vec_free [i] xparams ) ^ ( mcp_tool_result_error `the "update" source may not contain a backtick character` ) } {}
        ? >= ( nurl_str_find upd `double update` ) 0 {} {
            ( vec_free [f] state ) ( vec_free [i] xparams )
            ^ ( mcp_tool_result_error `"update" must define __device__ double update(long long j, const double* p) returning the new state[j]; read swarm_state(i), swarm_acc(i), swarm_N and swarm_param(i)` )
        }
    } {}
    // resolve range (a dataset defaults [0, count))
    : ~ i rlo ?? ( json_obj_get args `lo` ) { T x → ?? ( json_num_as_i x ) { T v → v F → -1 } F → -1 }
    : ~ i rhi ?? ( json_obj_get args `hi` ) { T x → ?? ( json_num_as_i x ) { T v → v F → -1 } F → -1 }
    ? != dsid 0 {
        : s dsp ( ds_find dsid )
        ? == # i dsp 0 { ( vec_free [f] state ) ( vec_free [i] xparams ) ^ ( mcp_tool_result_error `no such dataset — upload one with compute_upload_data` ) } {}
        : *Dataset d # *Dataset dsp
        ? < rlo 0 { = rlo 0 } {}
        ? < rhi 0 { = rhi ( ds_count_of d ) } {}
        ? | | < rlo 0 > rhi ( ds_count_of d ) >= rlo rhi { ( vec_free [f] state ) ( vec_free [i] xparams ) ^ ( mcp_tool_result_error `the range [lo, hi) must lie within the dataset` ) } {}
    } {
        ? & >= rlo 0 > rhi rlo {} { ( vec_free [f] state ) ( vec_free [i] xparams ) ^ ( mcp_tool_result_error `"lo" and "hi" are required without a "dataset" (lo < hi)` ) }
    }
    : i N - rhi rlo
    : i has_params 1  // state (+ params) always rides as params
    : i has_data ? != dsid 0 1 0
    // build the vecreduce (accumulate) module ONCE (source-hash cached; the
    // state is a param, so the SAME module serves every round — no rebuild,
    // warm worker cache). In general mode also build the update module.
    : String wrapped ( cuda_wrap cuda 0 ( gpu_mode_vecreduce ) has_params has_data )
    : ( Vec u ) srcb ( bytes_from_str ( string_data wrapped ) )
    : String hex ( _wasm_hash srcb )
    ( vec_free [u] srcb )
    : ~ ( Vec u ) wasm ( vec_new [u] )
    : ~ b have F
    ?? ( __wcache_get ( string_data hex ) ) { T hitw → { ( vec_free [u] wasm ) = wasm hitw = have T } F → {} }
    ? ! have {
        : !( Vec u ) String cr ( compile_to_wasm ( string_data wrapped ) )
        ?? cr {
            F msg → {
                : String em ( string_concat ( string_from `the accumulate (grad) kernel did not compile: ` ) msg )
                : Json e ( mcp_tool_result_error ( string_data em ) )
                ( string_free em ) ( string_free msg ) ( string_free wrapped ) ( string_free hex )
                ( vec_free [f] state ) ( vec_free [i] xparams ) ( vec_free [u] wasm )
                ^ e
            }
            T builtw → { ( vec_free [u] wasm ) = wasm builtw ( __wcache_put ( string_data hex ) wasm ) }
        }
    } {}
    ( string_free wrapped ) ( string_free hex )
    : ~ ( Vec u ) uwasm ( vec_new [u] )
    ? have_update {
        : String uwrapped ( cuda_wrap_update upd S A )
        : ( Vec u ) usrcb ( bytes_from_str ( string_data uwrapped ) )
        : String uhex ( _wasm_hash usrcb )
        ( vec_free [u] usrcb )
        : ~ b uhave F
        ?? ( __wcache_get ( string_data uhex ) ) { T hitw → { ( vec_free [u] uwasm ) = uwasm hitw = uhave T } F → {} }
        ? ! uhave {
            : !( Vec u ) String ucr ( compile_to_wasm ( string_data uwrapped ) )
            ?? ucr {
                F msg → {
                    : String em ( string_concat ( string_from `the update kernel did not compile: ` ) msg )
                    : Json e ( mcp_tool_result_error ( string_data em ) )
                    ( string_free em ) ( string_free msg ) ( string_free uwrapped ) ( string_free uhex )
                    ( vec_free [f] state ) ( vec_free [i] xparams ) ( vec_free [u] wasm ) ( vec_free [u] uwasm )
                    ^ e
                }
                T builtw → { ( vec_free [u] uwasm ) = uwasm builtw ( __wcache_put ( string_data uhex ) uwasm ) }
            }
        } {}
        ( string_free uwrapped ) ( string_free uhex )
    } {}
    // a dead relay here means the coordinator reconnects to the next in the
    // list before submitting — a relay failure does not take the API down
    ? ( mcp_ensure_relay ) {} {}
    : *Swarm sw ( mcp_swarm )
    ( swarm_discover sw 6 )
    : i ngpu ( roster_count_caps # *Roster . sw roster ( cap_gpu ) )
    ? == ngpu 0 { ( vec_free [f] state ) ( vec_free [i] xparams ) ( vec_free [u] wasm ) ( vec_free [u] uwasm ) ^ ( mcp_tool_result_error `no GPU workers in the cluster — start some with 'swarm-mcp --worker --gpu'` ) } {}
    // ── the loop, in the coordinator ──
    : *McpState st # *McpState g_mcp
    : *u nseed ( nurl_alloc 8 )
    ( nurl_poke nseed 0 0 )
    : ~ i total_seeded 0
    : ( Vec f ) grad ( vec_new [f] )
    : ( Vec f ) prev ( vec_new [f] )
    : ~ i ran 0
    : ~ i failed 0
    : ~ f last_delta 0.0
    : ~ b converged F
    : ~ i rnd 0
    ~ & < rnd rounds ! converged {
        ( nurl_poke nseed 0 0 )
        : i nf ( __iterate_round sw wasm S A xparams rlo rhi state dsid . st seeded nseed grad )
        = total_seeded + total_seeded ( nurl_peek nseed 0 )
        ? > nf 0 { = failed nf = rnd rounds } {
            ? have_update {
                // general step: new_state = update(acc, state, N, params) as a
                // sample over [0, S) on a GPU worker; delta vs the snapshot.
                ( vec_clear [f] prev )
                : ~ i sj 0
                ~ < sj S { ( vec_push [f] prev ?? ( vec_get [f] state sj ) { T x → x F → 0.0 } ) = sj + sj 1 }
                : i nfu ( __iterate_update sw uwasm S A grad N xparams state )
                ? > nfu 0 { = failed nfu = rnd rounds } {
                    : ~ f dmax 0.0
                    : ~ i j 0
                    ~ < j S {
                        : f nv ?? ( vec_get [f] state j ) { T x → x F → 0.0 }
                        : f ov ?? ( vec_get [f] prev j ) { T x → x F → 0.0 }
                        : f d - nv ov
                        : f ad ? < d 0.0 - 0.0 d d
                        ? > ad dmax { = dmax ad } {}
                        = j + j 1
                    }
                    = last_delta dmax = ran + ran 1
                    ? & > eps 0.0 < dmax eps { = converged T } {}
                }
            } {
                // SGD update: theta[j] -= lr * grad[j] / N ; track max |delta|
                : ~ f dmax 0.0
                : ~ i j 0
                ~ < j S {
                    : f g ?? ( vec_get [f] grad j ) { T x → x F → 0.0 }
                    : f d / * lr g # f N
                    : f cur ?? ( vec_get [f] state j ) { T x → x F → 0.0 }
                    ( vec_set [f] state j - cur d )
                    : f ad ? < d 0.0 - 0.0 d d
                    ? > ad dmax { = dmax ad } {}
                    = j + j 1
                }
                = last_delta dmax
                = ran + ran 1
                ? & > eps 0.0 < dmax eps { = converged T } {}
            }
        }
        = rnd + rnd 1
    }
    ( nurl_free nseed )
    ( vec_free [u] wasm ) ( vec_free [u] uwasm ) ( vec_free [i] xparams ) ( vec_free [f] prev )
    // ── the result ──
    ? > failed 0 {
        ( vec_free [f] grad ) ( vec_free [f] state )
        ^ ( mcp_tool_result_error `a chunk failed on a worker (bad kernel, missing GPU, or a lost block) — the run was stopped` )
    } {}
    : Json o ( json_obj_new )
    : Json sarr ( json_arr_new )
    : ~ i j2 0
    ~ < j2 S { : b _p ( json_arr_push sarr ( json_float ?? ( vec_get [f] state j2 ) { T x → x F → 0.0 } ) ) = j2 + j2 1 }
    ( json_obj_set o `state` sarr )
    ( json_obj_set o `rounds_run` ( json_int ran ) )
    ( json_obj_set o `converged` ( json_bool converged ) )
    ( json_obj_set o `last_max_delta` ( json_float last_delta ) )
    ? != dsid 0 { ( json_obj_set o `dataset` ( json_int dsid ) ) ( json_obj_set o `seeded_blocks` ( json_int total_seeded ) ) } {}
    ( vec_free [f] grad ) ( vec_free [f] state )
    ^ ( tool_result_json o )
}

// ── the shuffle primitive: compute_shuffle (group-by / reduce-by-key) ──
// BOTH the map AND the per-key reduce run distributed on the GPU: each chunk
// maps its elements to (key, value) and reduces them by key on the device,
// into a compact K-slot open-addressing table (a MapReduce combiner). The
// coordinator only MERGES the small per-chunk partial tables — the O(N)
// per-key accumulation never touches the coordinator. The result is still
// capped at 65 536 distinct keys (a text result can't carry more), and the
// input range at 8 M elements, but the reduce work now scales with the
// cluster rather than the coordinator.
// Merge a partial value (from a worker's per-chunk reduced table) into the
// running group total. Unlike __shuffle_put (which folded raw pairs and so
// counted +1 per pair), the workers already reduced their chunk, so EVERY op
// — count included — combines partials associatively via red_combine_f
// (count's partials are per-chunk counts, summed).
@ __shuffle_merge ( HashMap i f ) m i key f v i op → v {
    : f cur ?? ( map_get [i f] m key \ i x → i { ^ ( hash_int x ) } \ i a i b → b { ^ ( eq_int a b ) } ) { T x → x F → ( red_id_f op ) }
    : f nv ( red_combine_f op cur v )
    : ?f _o ( map_set [i f] m key nv \ i x → i { ^ ( hash_int x ) } \ i a i b → b { ^ ( eq_int a b ) } )
}

// Smallest power of two ≥ n (the open-addressing table needs a pow-2 size so
// the kernel can mask with K−1). n is 2× the distinct-key upper bound.
@ __next_pow2 i n → i {
    : ~ i p 1
    ~ < p n { = p * p 2 }
    ^ p
}

@ __shuffle_cap → i { ^ 8388608 }  // ≤ 8 M input elements per shuffle
@ __shuffle_keys_cap → i { ^ 65536 }  // ≤ 65 536 distinct groups in a text result

@ tool_shuffle Json args → Json {
    : ?Json cj ( json_obj_get args `map` )
    : b have_map ?? cj { T _ → T F → F }
    ? have_map {} { ^ ( mcp_tool_result_error `compute_shuffle needs "map" — a pair of CUDA device functions __device__ long long key(long long x[, double v][, const double* p]) and __device__ double value(...) that emit one (key, value) per element — plus "reduce" (sum|product|min|max|count) and "lo"/"hi" (or "dataset")` ) }
    : s cuda ?? cj { T x → ( json_str_data x ) F → `` }
    : i op ?? ( json_obj_get args `reduce` ) { T v → ( reduce_op_of ( json_str_data v ) 0 ) F → 0 }
    : i dsid ?? ( json_obj_get args `dataset` ) { T x → ?? ( json_num_as_i x ) { T v → v F → 0 } F → 0 }
    : ?( Vec i ) pp ( __parse_params args )
    ? ?? pp { T _ → T F → F } {} { ^ ( mcp_tool_result_error `"params" must be an array of numbers` ) }
    : ( Vec i ) params ?? pp { T v → v F → ( vec_new [i] ) }
    ? ! ( cuda_src_ok cuda ) { ( vec_free [i] params ) ^ ( mcp_tool_result_error `the CUDA source may not contain a backtick character` ) } {}
    ? & >= ( nurl_str_find cuda `long long key` ) 0 >= ( nurl_str_find cuda `double value` ) 0 {} {
        ( vec_free [i] params )
        ^ ( mcp_tool_result_error `the CUDA source must define __device__ long long key(long long x) and __device__ double value(long long x) — with a dataset both also take double v = data[x]; with params a trailing const double* p` )
    }
    : ~ i rlo ?? ( json_obj_get args `lo` ) { T x → ?? ( json_num_as_i x ) { T v → v F → -1 } F → -1 }
    : ~ i rhi ?? ( json_obj_get args `hi` ) { T x → ?? ( json_num_as_i x ) { T v → v F → -1 } F → -1 }
    : ~ s dsp # s 0
    ? != dsid 0 {
        = dsp ( ds_find dsid )
        ? == # i dsp 0 { ( vec_free [i] params ) ^ ( mcp_tool_result_error `no such dataset — upload one with compute_upload_data` ) } {}
        : *Dataset d # *Dataset dsp
        ? < rlo 0 { = rlo 0 } {}
        ? < rhi 0 { = rhi ( ds_count_of d ) } {}
        ? | | < rlo 0 > rhi ( ds_count_of d ) >= rlo rhi { ( vec_free [i] params ) ^ ( mcp_tool_result_error `the range [lo, hi) must lie within the dataset` ) } {}
    } {
        ? & >= rlo 0 > rhi rlo {} { ( vec_free [i] params ) ^ ( mcp_tool_result_error `"lo" and "hi" are required without a "dataset" (lo < hi)` ) }
    }
    ? > - rhi rlo ( __shuffle_cap ) { ( vec_free [i] params ) ^ ( mcp_tool_result_error `shuffle range too large: hi - lo must be <= 8388608 (the coordinator holds the intermediate (key,value) pairs)` ) } {}
    : i has_params ? > ( vec_len [i] params ) 0 1 0
    : i has_data ? != dsid 0 1 0
    // per-chunk hash-table size: a power of two ≥ 2× the distinct-key upper
    // bound (a chunk can hold no more distinct keys than the whole range, and
    // the result is capped at __shuffle_keys_cap anyway). Keeps the load
    // factor ≤ ½ so the open-addressing reduce never probes the full table.
    : i span0 - rhi rlo
    : i kkap ( __shuffle_keys_cap )
    : ~ i ktab ( __next_pow2 * 2 ? < span0 kkap span0 kkap )
    ? < ktab 256 { = ktab 256 } {}
    // build the shuffle_reduce module once (source-hash cached); op is baked
    // into the kernel (the reduce atomic and the identity), so distinct ops
    // key distinct modules.
    : String wrapped ( cuda_wrap cuda op ( gpu_mode_shuffle_reduce ) has_params has_data )
    : ( Vec u ) srcb ( bytes_from_str ( string_data wrapped ) )
    : String hex ( _wasm_hash srcb )
    ( vec_free [u] srcb )
    : ~ ( Vec u ) wasm ( vec_new [u] )
    : ~ b have F
    ?? ( __wcache_get ( string_data hex ) ) { T hitw → { ( vec_free [u] wasm ) = wasm hitw = have T } F → {} }
    ? ! have {
        : !( Vec u ) String cr ( compile_to_wasm ( string_data wrapped ) )
        ?? cr {
            F msg → {
                : String em ( string_concat ( string_from `the shuffle reduce program did not compile: ` ) msg )
                : Json e ( mcp_tool_result_error ( string_data em ) )
                ( string_free em ) ( string_free msg ) ( string_free wrapped ) ( string_free hex )
                ( vec_free [i] params ) ( vec_free [u] wasm )
                ^ e
            }
            T builtw → { ( vec_free [u] wasm ) = wasm builtw ( __wcache_put ( string_data hex ) wasm ) }
        }
    } {}
    ( string_free wrapped ) ( string_free hex )
    ? ( mcp_ensure_relay ) {} {}
    : *Swarm sw ( mcp_swarm )
    ( swarm_discover sw 6 )
    : i ngpu ( roster_count_caps # *Roster . sw roster ( cap_gpu ) )
    ? == ngpu 0 { ( vec_free [i] params ) ( vec_free [u] wasm ) ^ ( mcp_tool_result_error `no GPU workers in the cluster — start some with 'swarm-mcp --worker --gpu'` ) } {}
    // each chunk returns a compact 16·K-byte partial table (not O(span)), so
    // chunking is purely about spreading the map+reduce across the ring
    : i span - rhi rlo
    : ~ i nchunks ( nchunks_wasm ngpu )
    ? > nchunks span { = nchunks span } {}
    : *McpState st # *McpState g_mcp
    : *u nseed ( nurl_alloc 8 )
    ( nurl_poke nseed 0 0 )
    : ~ ( Vec i ) tids ( vec_new [i] )
    ? != dsid 0 {
        : *Dataset d # *Dataset dsp
        ( vec_free [i] tids )
        = tids ( cluster_submit_wasm_gpu_ds sw ( gpu_mode_shuffle_reduce ) rlo rhi ktab params d wasm nchunks . st seeded nseed )
    } {
        : ( Vec u ) dbytes ( vec_new [u] )
        ( vec_free [i] tids )
        = tids ( cluster_submit_wasm_gpu sw ( gpu_mode_shuffle_reduce ) rlo rhi ktab params dbytes wasm nchunks )
        ( vec_free [u] dbytes )
    }
    ( nurl_free nseed )
    ( vec_free [i] params ) ( vec_free [u] wasm )
    // drive to completion, collect the concatenated per-chunk partial tables
    : ~ i r 0
    ~ & < r 6000 ! ( tids_ready sw tids ) { ( swarm_pump sw 100 ) = r + r 1 }
    : CombinedV cv ( tids_combine_vec sw ( gpu_mode_shuffle_reduce ) ktab tids )
    ( vec_free [i] tids )
    ? > . cv nfail 0 {
        ( vec_free [u] . cv bytes )
        ^ ( mcp_tool_result_error `a shuffle chunk failed on a worker (bad kernel, missing GPU, or a lost block)` )
    } {}
    // ── merge the partial tables: fold each key's per-chunk partials ──
    // slots hold (i64 key, f64 val); an empty slot's key is LLONG_MIN (1<<63)
    : ( HashMap i f ) groups ( map_new [i f] )
    : i nbytes ( vec_len [u] . cv bytes )
    : i nslots / nbytes 16
    : i empty_key << 1 63
    : ~ i k 0
    ~ < k nslots {
        : i key ( __f64le_get . cv bytes * k 16 )
        ? != key empty_key {
            : f val ( bits_to_f64 ( __f64le_get . cv bytes + * k 16 8 ) )
            ( __shuffle_merge groups key val op )
        } {}
        = k + k 1
    }
    ( vec_free [u] . cv bytes )
    : i ngroups ( map_len [i f] groups )
    ? > ngroups ( __shuffle_keys_cap ) {
        ( map_free [i f] groups )
        ^ ( mcp_tool_result_error `more than 65536 distinct keys — narrow the range or coarsen the key function (a text result cannot carry a larger group table)` )
    } {}
    : Json go ( json_obj_new )
    ( map_each [i f] groups \ i kk f vv → v {
        : s ks ( nurl_str_int kk )
        : b _o ( json_obj_set go ks ( json_float vv ) )
        ( nurl_free # s ks )
    } )
    ( map_free [i f] groups )
    : Json o ( json_obj_new )
    ( json_obj_set o `groups` go )
    ( json_obj_set o `n_groups` ( json_int ngroups ) )
    ( json_obj_set o `reduce` ( json_str_lit ( reduce_op_name op ) ) )
    ( json_obj_set o `pairs_mapped` ( json_int span ) )
    ( json_obj_set o `distributed_reduce` ( json_bool T ) )
    ^ ( tool_result_json o )
}

@ tool_submit_cuda Json args → Json {
    : ?Json cj ( json_obj_get args `cuda` )
    ? ! ?? cj { T _ → T F → F } {
        ^ ( mcp_tool_result_error `compute_submit_cuda needs "cuda" (a __device__ double f(long long x) function) plus "lo"/"hi" (or "dataset"); "reduce"/"params" optional` )
    } {}
    : s cuda ?? cj { T v → ( json_str_data v ) F → `` }
    : i lo ?? ( json_obj_get args `lo` ) { T v → ( json_as_int v ) F → - 0 1 }
    : i hi ?? ( json_obj_get args `hi` ) { T v → ( json_as_int v ) F → - 0 1 }
    : i op ?? ( json_obj_get args `reduce` ) { T v → ( reduce_op_of ( json_str_data v ) 0 ) F → 0 }
    : i dsid ?? ( json_obj_get args `dataset` ) { T v → ( json_as_int v ) F → 0 }
    ?? ( __parse_params args ) {
        F → { ^ ( mcp_tool_result_error `"params" must be an array of numbers` ) }
        T params → { ^ ( __submit_cuda_task cuda op ( gpu_mode_scalar ) lo hi 0 params `` dsid ) }
    }
}

// compute_sample_cuda: every f(x) comes back — the cluster gathers the range
// into one array (curves, fields, images).
@ tool_sample_cuda Json args → Json {
    : ?Json cj ( json_obj_get args `cuda` )
    : ?Json lj ( json_obj_get args `lo` )
    : ?Json hj ( json_obj_get args `hi` )
    ? ! ?? cj { T _ → T F → F } {
        ^ ( mcp_tool_result_error `compute_sample_cuda needs "cuda" (a __device__ double f(long long x) function) plus "lo"/"hi" (or "dataset"); "params"/"out_file" optional` )
    } {}
    : s cuda ?? cj { T v → ( json_str_data v ) F → `` }
    : i lo ?? lj { T v → ( json_as_int v ) F → - 0 1 }
    : i hi ?? hj { T v → ( json_as_int v ) F → - 0 1 }
    : s out_file ?? ( json_obj_get args `out_file` ) { T v → ( json_str_data v ) F → `` }
    : i dsid ?? ( json_obj_get args `dataset` ) { T v → ( json_as_int v ) F → 0 }
    ?? ( __parse_params args ) {
        F → { ^ ( mcp_tool_result_error `"params" must be an array of numbers` ) }
        T params → { ^ ( __submit_cuda_task cuda 0 ( gpu_mode_sample ) lo hi 0 params out_file dsid ) }
    }
}

// compute_histogram_cuda: bin(x) picks a bucket, val(x) the weight (default
// 1.0); K bin sums come back — a whole distribution in one pass.
@ tool_hist_cuda Json args → Json {
    : ?Json cj ( json_obj_get args `cuda` )
    : ?Json kj ( json_obj_get args `bins` )
    ? | ! ?? cj { T _ → T F → F } ! ?? kj { T _ → T F → F } {
        ^ ( mcp_tool_result_error `compute_histogram_cuda needs "cuda" (a __device__ long long bin(long long x) function) and "bins" (int), plus "lo"/"hi" (or "dataset"); "params"/"out_file" optional` )
    } {}
    : s cuda ?? cj { T v → ( json_str_data v ) F → `` }
    : i lo ?? ( json_obj_get args `lo` ) { T v → ( json_as_int v ) F → - 0 1 }
    : i hi ?? ( json_obj_get args `hi` ) { T v → ( json_as_int v ) F → - 0 1 }
    : i kbins ?? kj { T v → ( json_as_int v ) F → 0 }
    : s out_file ?? ( json_obj_get args `out_file` ) { T v → ( json_str_data v ) F → `` }
    : i dsid ?? ( json_obj_get args `dataset` ) { T v → ( json_as_int v ) F → 0 }
    ? | < kbins 1 > kbins 1048576 { ^ ( mcp_tool_result_error `"bins" must be between 1 and 1048576` ) } {}
    ? & > kbins ( __vres_b64_max ) == ( nurl_str_len out_file ) 0 {
        ^ ( mcp_tool_result_error `more than 65536 bins needs "out_file" (an absolute path on the MCP host) — the bins cannot ride a text result` )
    } {}
    ?? ( __parse_params args ) {
        F → { ^ ( mcp_tool_result_error `"params" must be an array of numbers` ) }
        T params → { ^ ( __submit_cuda_task cuda 0 ( gpu_mode_hist ) lo hi kbins params out_file dsid ) }
    }
}

// ── tools: compute_upload_data / compute_list_data ───────────────
// A dataset arrives as base64 raw LE f64s, or as a file path on the MCP
// host; it is held at the coordinator and mapped over by the CUDA tools.

@ __ds_max_bytes → i { ^ 268435456 }  // 256 MiB

@ tool_upload_data Json args → Json {
    : s b64 ?? ( json_obj_get args `data_base64` ) { T v → ( json_str_data v ) F → `` }
    : s fpath ?? ( json_obj_get args `file` ) { T v → ( json_str_data v ) F → `` }
    : s name ?? ( json_obj_get args `name` ) { T v → ( json_str_data v ) F → `` }
    ? & == ( nurl_str_len b64 ) 0 == ( nurl_str_len fpath ) 0 {
        ^ ( mcp_tool_result_error `compute_upload_data needs "data_base64" (raw little-endian f64s) or "file" (a path on the MCP host); "name" optional` )
    } {}
    : ~ ( Vec u ) bytes ( vec_new [u] )
    : ~ b got F
    ? > ( nurl_str_len b64 ) 0 {
        ?? ( b64_decode_vec b64 ) {
            T v → { ( vec_free [u] bytes ) = bytes v = got T }
            F e → {}
        }
    } {
        ?? ( read_file_bytes fpath ) {
            T v → { ( vec_free [u] bytes ) = bytes v = got T }
            F e → {}
        }
    }
    ? ! got {
        ( vec_free [u] bytes )
        ^ ( mcp_tool_result_error `could not read the dataset (invalid base64, or the file is unreadable on the MCP host)` )
    } {}
    : i blen ( vec_len [u] bytes )
    ? | | == blen 0 != % blen 8 0 > blen ( __ds_max_bytes ) {
        ( vec_free [u] bytes )
        ^ ( mcp_tool_result_error `a dataset must be 1..33554432 f64 values: non-empty, a multiple of 8 bytes, at most 256 MiB` )
    } {}
    : *McpState st # *McpState g_mcp
    : *Dataset d # *Dataset ( nurl_alloc Z Dataset )
    = . d id . st next_ds
    = . st next_ds + . st next_ds 1
    = . d name ( string_from name )
    = . d bytes bytes
    // the content-address manifest: BLAKE3 per 1 MiB block (blob.nu) — the
    // transfer unit workers cache, so re-submits and iteration rounds
    // reference data by hash instead of re-shipping it
    = . d blocks ( blob_manifest . d bytes )
    ( vec_push [s] . st datasets # s d )
    : Json o ( json_obj_new )
    ( json_obj_set o `dataset_id` ( json_int . d id ) )
    ? > ( nurl_str_len name ) 0 { ( json_obj_set o `name` ( json_str_lit name ) ) } {}
    ( json_obj_set o `count` ( json_int ( ds_count_of d ) ) )
    ( __stats_json o . d bytes )
    ^ ( tool_result_json o )
}

@ tool_list_data Json args → Json {
    : *McpState st # *McpState g_mcp
    : Json arr ( json_arr_new )
    : i n ( vec_len [s] . st datasets )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . st datasets k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Dataset d # *Dataset pp
            : Json o ( json_obj_new )
            ( json_obj_set o `dataset_id` ( json_int . d id ) )
            ? > ( string_len . d name ) 0 { ( json_obj_set o `name` ( json_str_lit ( string_data . d name ) ) ) } {}
            ( json_obj_set o `count` ( json_int ( ds_count_of d ) ) )
            ( json_arr_push arr o )
        } {}
        = k + k 1
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `datasets` arr )
    ^ ( tool_result_json o )
}

// ── tool: compute_list ───────────────────────────────────────────

@ tool_list Json args → Json {
    ( mcp_pump 4 )
    : *McpState st # *McpState g_mcp
    : Json arr ( json_arr_new )
    : i n ( vec_len [s] . st tasks )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . st tasks k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Task t # *Task pp
            ( task_refresh t )
            ( json_arr_push arr ( task_to_json t ) )
        } {}
        = k + k 1
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `tasks` arr )
    ^ ( tool_result_json o )
}

// ── tool: compute_result ─────────────────────────────────────────

@ tool_result Json args → Json {
    : ?Json idj ( json_obj_get args `task_id` )
    ? ! ?? idj { T _ → T F → F } { ^ ( mcp_tool_result_error `compute_result needs "task_id" (int)` ) } {}
    : i id ?? idj { T v → ( json_as_int v ) F → 0 }
    ( mcp_pump 4 )
    : s tp ( task_find id )
    ? == # i tp 0 { ^ ( mcp_tool_result_error `no such task_id` ) } {}
    : *Task t # *Task tp
    ( task_refresh t )
    ^ ( tool_result_json ( task_to_json t ) )
}

// ── tool descriptors ─────────────────────────────────────────────

@ ms_prop Json props s name s ty s desc → v {
    : Json p ( json_obj_new )
    ( json_obj_set p `type` ( json_str_lit ty ) )
    ( json_obj_set p `description` ( json_str_lit desc ) )
    ( json_obj_set props name p )
}

@ ms_schema_submit → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `expr` `string` `The kernel: an expression in x — operators + - * / %, comparisons, logical & |, ternary ?:, min/max/abs; int or float literals. E.g. "x*x", "x%2==0", "x>5 ? x : 0". Full grammar: swarm_help "expr".` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `reduce` `string` `Fold: "sum" (default) · product · min · max · count (how many x make the kernel nonzero).` )
    ( ms_prop props `dtype` `string` `"int" (default, i64; x is the index) or "float" (f64; x is the index as a double). E.g. {"expr":"1.0/(x*x)",…,"dtype":"float"} ≈ π²/6.` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `expr` ) )
    ( json_arr_push req ( json_str_lit `lo` ) )
    ( json_arr_push req ( json_str_lit `hi` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_result → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `task_id` `integer` `The id returned by compute_submit.` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `task_id` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_empty → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    ^ schema
}

@ ms_schema_run_wasm → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `wasm_base64` `string` `Base64 wasm32-wasi module (e.g. from nurl_build_wasm). Its main reads lo, hi from argv, folds your kernel over [lo, hi), and prints the partial as a decimal integer.` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `reduce` `string` `Combine the per-worker partials: "sum" (default) · product · min · max · count. Must match what the module reduces with.` )
    ( ms_prop props `dtype` `string` `"int" (default; prints a decimal-integer partial) or "float" (prints the f64 bit pattern, e.g. floatbits f64_to_bits; combined in f64).` )
    ( ms_prop props `gpu` `boolean` `Route only to --gpu workers and run with GPU host imports live (cuda/nvrtc FFI in the module hits the real GPU). Default false. See swarm_help "gpu".` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `wasm_base64` ) )
    ( json_arr_push req ( json_str_lit `lo` ) )
    ( json_arr_push req ( json_str_lit `hi` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_submit_kernel → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `source` `string` `NURL source with a per-element kernel @ kernel i x → i { … } (+ optional imports/helpers; no main — the server generates it and compiles to wasm). For dtype "float" use → f. E.g. @ is_prime i n → b { … }  @ kernel i x → i { ? ( is_prime x ) 1 0 } with reduce "sum" counts primes.` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `reduce` `string` `Combine the per-worker partials: "sum" (default) · product · min · max · count.` )
    ( ms_prop props `dtype` `string` `"int" (default; kernel returns i) or "float" (kernel returns f, folded in f64).` )
    ( ms_prop props `gpu` `boolean` `Route only to --gpu workers, GPU host imports live (cuda/nvrtc FFI in your source hits the real GPU). Default false.` )
    ( ms_prop props `kind` `string` `"element" (default; @ kernel i x → i/f per x) or "chunk" (@ kernel i lo i hi → i/f, called once per sub-range — the kernel owns the loop). Use "chunk" for per-invocation setup (GPU ctx + JIT).` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `source` ) )
    ( json_arr_push req ( json_str_lit `lo` ) )
    ( json_arr_push req ( json_str_lit `hi` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

// The params property text is shared by all three CUDA tools.
@ __ms_params_desc → s {
    ^ `Optional numbers passed to your device functions as a trailing const double* p (read p[0], p[1], …). Values never recompile the kernel, so parameter scans stay interactive. See swarm_help "cuda".`
}
// The dataset property text is shared by the CUDA map tools.
@ __ms_dataset_desc → s {
    ^ `Optional dataset id (compute_upload_data): map over the DATA — device functions gain a second argument double v = data[x]. Omit lo/hi for the whole dataset. See swarm_help "datasets".`
}

@ ms_schema_submit_cuda → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `cuda` `string` `A CUDA-C __device__ double f(long long x) (with params: f(long long x, const double* p)). __device__ only — no __global__/host/#includes; NVRTC builtins (sin, exp, sqrt, fmin…) available; no backticks. E.g. "__device__ double f(long long x){ double t=(double)x*1e-9; return 4.0/(1.0+t*t); }". Full ABI: swarm_help "cuda".` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `reduce` `string` `Fold f(x): "sum" (default) · product · min · max · count (how many f(x) != 0).` )
    ( ms_prop props `dataset` `integer` ( __ms_dataset_desc ) )
    ( ms_prop props `params` `array` ( __ms_params_desc ) )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `cuda` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_shuffle → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `map` `string` `CUDA-C __device__ long long key(long long x) and __device__ double value(long long x) — emit (key, value) per element (with a dataset both take double v = data[x]). E.g. "__device__ long long key(long long x){ return x%100; } __device__ double value(long long x){ return 1.0; }". Details: swarm_help "shuffle".` )
    ( ms_prop props `reduce` `string` `Fold values that share a key: "sum" (default) · product · min · max · count (pairs per key).` )
    ( ms_prop props `dataset` `integer` ( __ms_dataset_desc ) )
    ( ms_prop props `lo` `integer` `Range start (inclusive); required without a dataset.` )
    ( ms_prop props `hi` `integer` `Range end (exclusive); required without a dataset. hi - lo ≤ 8388608, ≤ 65536 keys.` )
    ( ms_prop props `params` `array` ( __ms_params_desc ) )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `map` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_iterate → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `cuda` `string` `CUDA-C __device__ void grad(long long x, double* g, const double* p) that scatter-adds via swarm_g_add(g, j, val) (with a dataset: grad(long long x, double v, double* g, const double* p), v = data[x]); p[0..state_len) is the current state, p[state_len..) your "params". Full ABI + examples: swarm_help "iterate".` )
    ( ms_prop props `state` `array` `Initial parameter vector (numbers), ≤ 4096. What the engine iterates and returns. Carry optimizer state (momentum/Adam moments) as extra components.` )
    ( ms_prop props `rounds` `integer` `Max rounds (1..100000). The loop runs IN THE ENGINE — you get the converged parameters back from one call.` )
    ( ms_prop props `lr` `number` `Default (SGD) mode: learning rate; each round state[j] -= lr*grad[j]/N. Required unless "update" is given (then ignored).` )
    ( ms_prop props `update` `string` `Optional CUDA-C step rule for a general fixpoint (k-means, EM, power iteration, Adam): __device__ double update(long long j, const double* p) returns the new state[j], reading swarm_state(i)/swarm_acc(i)/swarm_N/swarm_param(i) (swarm_dim, swarm_adim for loops). With it the accumulator may be wider than the state (set "acc_dim"). Recipes: swarm_help "iterate".` )
    ( ms_prop props `acc_dim` `integer` `Accumulator width (1..65536) when grad() scatters into more slots than the state length (k-means sum+count, EM stats, A·v). Defaults to the state length; needs "update" when different.` )
    ( ms_prop props `params` `array` `Optional constant numbers (same every round): grad reads p[state_len..], update reads swarm_param(i).` )
    ( ms_prop props `epsilon` `number` `Optional: stop early once the largest |state change| in a round is below this. Omit to run all "rounds".` )
    ( ms_prop props `dataset` `integer` `Optional dataset id: grad maps over the data (v = data[x]); blocks cache after round one, so later rounds ship only the state.` )
    ( ms_prop props `lo` `integer` `Range start (inclusive); required without a dataset.` )
    ( ms_prop props `hi` `integer` `Range end (exclusive); required without a dataset.` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `cuda` ) )
    ( json_arr_push req ( json_str_lit `state` ) )
    ( json_arr_push req ( json_str_lit `rounds` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_sample_cuda → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `cuda` `string` `CUDA-C __device__ double f(long long x) (with params/dataset: extra args) — same rules as compute_submit_cuda, but every value comes back instead of being reduced. ABI: swarm_help "cuda".` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). hi - lo values returned; ≤ 1048576 (≤ 65536 without out_file).` )
    ( ms_prop props `dataset` `integer` ( __ms_dataset_desc ) )
    ( ms_prop props `params` `array` ( __ms_params_desc ) )
    ( ms_prop props `out_file` `string` `Optional absolute path ON THE MCP HOST: values written there as raw LE f64s (count = hi - lo), the text result carrying only count + min/max/mean. Required beyond 65536 values.` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `cuda` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_hist_cuda → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `cuda` `string` `CUDA-C __device__ long long bin(long long x) picks the bucket (out-of-range skipped); optional __device__ double val(long long x) is the weight (default 1.0 = counting). With params/dataset: extra args. ABI: swarm_help "cuda".` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `bins` `integer` `Bucket count K (1..1048576; ≤ 65536 without out_file). The result is K sums.` )
    ( ms_prop props `dataset` `integer` ( __ms_dataset_desc ) )
    ( ms_prop props `params` `array` ( __ms_params_desc ) )
    ( ms_prop props `out_file` `string` `Optional absolute path ON THE MCP HOST: bins written there as raw LE f64s, the text result carrying only count + min/max/mean. Required beyond 65536 bins.` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `cuda` ) )
    ( json_arr_push req ( json_str_lit `bins` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ ms_schema_upload_data → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `data_base64` `string` `The dataset as base64 of raw LITTLE-ENDIAN f64 values. Use this XOR "file".` )
    ( ms_prop props `file` `string` `A path ON THE MCP HOST to read the dataset from (raw little-endian f64s). Use this XOR "data_base64".` )
    ( ms_prop props `name` `string` `Optional human-readable label shown by compute_list_data.` )
    ( json_obj_set schema `properties` props )
    ^ schema
}

// ── swarm_help: on-demand, topic-queryable guidance ──────────────────
// The tool schemas stay short (cheap on every tools/list); the depth an LLM
// needs — the CUDA ABI, the iterate/shuffle recipes, and the honest size/
// support envelope — lives here, fetched one topic at a time.
@ __help_index → s {
    ^ `swarm-mcp help. The tool schemas are deliberately short; call swarm_help with a "topic" for depth on one area.\nTopics:\n  overview        — what this is: nodes, roles, the token, the compute model\n  workflow        — submit -> poll compute_result -> done/error; failed_chunks\n  expr            — the compute_submit expression language (int/float)\n  cuda            — the CUDA-C device-function ABI shared by every GPU tool\n  iterate         — compute_iterate: gradient descent AND general fixpoints (k-means, EM, power iteration)\n  shuffle         — compute_shuffle: group-by-key / reduce-by-key\n  datasets        — compute_upload_data: bring data once, referenced by hash\n  gpu             — --gpu workers, task routing, the trust boundary\n  limits          — sizes, caps, and what is NOT yet supported (read before scaling)\n  troubleshooting — common errors and what they mean\nExample: {"name":"swarm_help","arguments":{"topic":"iterate"}}`
}

@ __help_overview → s {
    ^ `swarm-mcp is a distributed compute cluster you drive over MCP. Every node runs the same binary; role flags compose: --relay (rendezvous point), --worker [--gpu] (runs kernels), --mcp (this control surface) — one process can be all three. A --token defines and secures a cluster: the same token forms one cluster (relay-group isolation + HMAC auth on every payload and result); nodes with different tokens are mutually invisible.\nYou set a workload; the cluster shards [lo,hi) across the eligible workers, runs a map kernel per element (or per chunk), and combines the partials with a reduce op (sum/product/min/max/count) — every op is associative, so the answer is independent of the worker count. Kernel flavours: a small integer/float EXPRESSION in x (compute_submit; topic "expr"), an arbitrary NURL program (compute_submit_kernel / compute_run_wasm), or CUDA-C device functions the server wraps into a GPU program (compute_submit_cuda and the sample/histogram/iterate/shuffle family; topic "cuda"). See topic "workflow" for the task lifecycle.`
}

@ __help_workflow → s {
    ^ `A submit tool returns immediately with a task_id and status "running" (or "done" for tiny work). Poll compute_result {"task_id":N} until status is "done" (result present) or "error". compute_list shows every task.\nThe coordinator drains cluster traffic on each tool call, so tasks advance as you poll — poll compute_result rather than sleeping.\nFailure is explicit: a chunk that traps (bad kernel, missing runtime or GPU, a lost dataset block) is COUNTED, never folded into the answer as zero. The task then finishes status "error" with failed_chunks>0 and withholds the result — a returned result always covers every chunk.\ncompute_iterate and compute_shuffle instead run their whole loop inside the single call and return the final answer directly (no polling).`
}

@ __help_expr → s {
    ^ `compute_submit evaluates an expression in one variable x over the integer range [lo,hi):\n  operators   + - * / %       (truncated division; /0 and %0 give 0)\n  comparisons < <= > >= == !=  (yield 1 or 0)\n  logical     & |             (on 0/1; nonzero is true)\n  ternary     cond ? a : b\n  functions   min(a,b) max(a,b) abs(a)\n  x, and integer or float literals\ndtype (default "int"): "int" = all i64, x is the index; "float" = all f64, x is the index cast to double, float literals like 0.5 allowed. The range [lo,hi) is integer in both.\nreduce: sum | product | min | max | count (count = how many x make map(x) nonzero).\nExamples: {"expr":"x*x","reduce":"sum"} ; {"expr":"x%2==0","reduce":"count"} ; {"expr":"x>100 ? x : 0","reduce":"sum"} ; {"expr":"1.0/(x*x)","reduce":"sum","dtype":"float"} ~ pi^2/6.\nFor loops or helper functions the expression cannot express, use compute_submit_kernel (arbitrary NURL) or the CUDA tools.`
}

@ __help_cuda → s {
    ^ `The GPU tools (compute_submit_cuda / _sample_cuda / _histogram_cuda / compute_iterate / compute_shuffle) take CUDA-C DEVICE FUNCTIONS only — you write the math and the server generates the whole program (NVRTC JIT, grid-stride map over the range, on-device reduction/atomics); the --gpu workers run it. Rules: __device__ functions only — no __global__, no host/main code, and NO backtick character anywhere.\nSignatures (x is the element index, a long long):\n  reduce    : __device__ double f(long long x)\n  sample    : the same f — every value is returned in order\n  histogram : __device__ long long bin(long long x)  [+ optional __device__ double val(long long x), default 1.0]\n  iterate   : __device__ void grad(long long x, double* g, const double* p)   (topic "iterate")\n  shuffle   : __device__ long long key(long long x) + __device__ double value(long long x)   (topic "shuffle")\nparams: pass "params":[numbers] and add a trailing const double* p, then read p[0], p[1], … . Parameter VALUES never recompile the kernel (cached by source hash and by content hash), so parameter scans run at interactive speed.\ndataset: pass "dataset":id and every device function gains a second argument double v = data[x] — e.g. f(long long x, double v, const double* p). See topic "datasets".`
}

@ __help_iterate → s {
    ^ `compute_iterate runs an iterative algorithm with the LOOP IN THE ENGINE: one call returns the converged "state". Each round (1) reduces a CUDA grad() over the range/dataset with the current state as params into an accumulator vector, (2) applies a step rule to get the next state, (3) stops at "rounds" or once the largest |state change| falls below "epsilon".\n\ngrad() scatter-adds each element's contribution:\n  __device__ void grad(long long x, double* g, const double* p) { swarm_g_add(g, j, val); ... }\n  with a dataset: grad(long long x, double v, double* g, const double* p), where v = data[x].\n  p[0..state_len) is the current state; p[state_len..) is your "params". swarm_g_add(g, j, val) adds val to accumulator component j (bounds-checked).\n\nTwo step rules:\n  DEFAULT (SGD) — give "lr". Each round: state[j] -= lr * grad[j] / N (N = element count). Here the accumulator must be the same length as state.\n  GENERAL — give an "update" device function; then anything works: k-means, EM, power iteration, PageRank, momentum/Adam.\n    __device__ double update(long long j, const double* p)   // returns the new state[j]\n    accessors inside update: swarm_state(i) = current state, swarm_acc(i) = the reduced accumulator (0..acc_dim), swarm_N = element count, swarm_param(i) = your "params"; swarm_dim (=state length) and swarm_adim (=acc_dim) are available for loops.\n    The accumulator may be WIDER than the state — set "acc_dim". A global reduction (e.g. a norm for power iteration) is just a loop over swarm_acc inside update. Carry optimizer state (momentum, Adam moments) as extra components of state and let update rewrite them.\n\nBounds: state <= 4096, acc_dim <= 65536, rounds <= 100000. Over a dataset the blocks cache on the workers after round one, so every later round ships only the state (seeded_blocks counts blocks moved over the whole run, not per round).\n\nExamples:\n  Fit the mean (SGD): grad "__device__ void grad(long long x, double v, double* g, const double* p){ swarm_g_add(g,0,2.0*(p[0]-v)); }", state [0], lr 0.4, dataset id.\n  1D k-means K=2 (general): state [c0,c1], acc_dim 4 (= [sum0,sum1,count0,count1]),\n    grad "__device__ void grad(long long x, double v, double* g, const double* p){ double d0=v-p[0]; if(d0<0)d0=-d0; double d1=v-p[1]; if(d1<0)d1=-d1; long long c=(d0<=d1)?0:1; swarm_g_add(g,c,v); swarm_g_add(g,2+c,1.0); }",\n    update "__device__ double update(long long j, const double* p){ double s=swarm_acc(j), n=swarm_acc(swarm_dim+j); return (n>0.0)?(s/n):swarm_state(j); }".\n  Power iteration (general): state = v (length n), grad builds A*v into acc_dim = n, update normalizes: loop swarm_acc for the norm, return swarm_acc(j)/norm.`
}

@ __help_shuffle → s {
    ^ `compute_shuffle is group-by-key / reduce-by-key. Give a CUDA map — __device__ long long key(long long x) and __device__ double value(long long x) — plus a reduce op. BOTH the map AND the per-key reduce run distributed on the GPU: each worker maps its chunk and reduces it by key on the device into a compact table (a MapReduce combiner), and the coordinator only merges the small per-chunk tables. Returns {"groups":{key:value, …}, "n_groups", "pairs_mapped", "distributed_reduce":true}.\nOver a dataset, key/value take double v = data[x]. A join is two shuffles into a shared key space, merged per key.\nLimits: hi - lo <= 8,388,608 per call, and <= 65,536 distinct keys (the group table rides a text result). For more, narrow the range or coarsen the key — see topic "limits".`
}

@ __help_datasets → s {
    ^ `compute_upload_data brings your data to the cluster: a flat f64 array, as {"data_base64": <raw little-endian f64>} or {"file": <path on the MCP host>}, up to 256 MiB (<= 33.5M values). Returns {dataset_id, count, min, max, mean}; compute_list_data lists them.\nThe data is cut into content-addressed 1 MiB blocks (BLAKE3). Each block travels to its owning worker ONCE and is cached on disk, verified against its hash on arrival. Later submits or iteration rounds over the same dataset ship only hashes — a task's seeded_blocks is how many blocks actually moved (0 = fully cached, a free re-run). A missing or corrupt block fails the chunk visibly, never silently.\nUse it: pass "dataset":id to compute_submit_cuda / _sample_cuda / _histogram_cuda / compute_iterate; the device functions then receive double v = data[x]. Omit lo/hi to process the whole dataset (a given range must lie within it). Data is f64 only — encode mixed/categorical data as doubles yourself (topic "limits").`
}

@ __help_gpu → s {
    ^ `GPU work needs workers started with --worker --gpu (and a wasmtime on PATH — the toolchain's pure-NURL packages/wasmtime is a drop-in). A --gpu worker advertises a capability bit, and GPU tasks route ONLY to such workers on a GPU-only consistent-hash ring, so a mixed CPU/GPU cluster just works; a CUDA tool on a CPU-only cluster returns a clear "no GPU workers" error.\nNo CUDA toolkit is needed on any node — only the driver's libcuda + libnvrtc. Kernels JIT at run time via NVRTC. Select the device with CUDA_VISIBLE_DEVICES in the worker's environment (the kernel binds device ordinal 0).\nTrust boundary: GPU host imports pierce the wasm sandbox by design (device pointers are raw host handles), so they are per-worker (--gpu) and, for the hand-written wasm paths, per-task (gpu:true) opt-in, on top of the cluster token — only token-authentic tasks reach a worker at all. Enable --gpu only for clusters whose token holders you trust.`
}

@ __help_limits → s {
    ^ `Read this before scaling. The current envelope and the edges that are NOT yet supported:\n  Dataset size: <= 256 MiB (<= 33.5M f64) per dataset; split larger data across datasets.\n  Data type: f64 ONLY — no int/f32/struct datasets. Encode categorical or mixed data as doubles yourself.\n  Shuffle: <= 8,388,608 input elements AND <= 65,536 distinct keys per call (the intermediate/result bound). High-cardinality group-by (e.g. per-user over millions of users) must be partitioned or the key coarsened, which changes semantics.\n  Sample: <= 1,048,576 values returned (inline <= 65,536; beyond needs out_file). Histogram: <= 1,048,576 bins.\n  Iterate: state <= 4096 components, acc_dim <= 65,536, rounds <= 100,000. SGD is built in; any other step rule goes through an "update" device function (topic "iterate").\n  Fault tolerance: a RELAY failure is survived — with --connect listing several relays, workers and the coordinator converge on a survivor mid-flight. But a WORKER that dies mid-task is NOT auto-redispatched: its chunk fails visibly (failed_chunks) and the task errors; resubmit to retry (datasets stay cached, so a resubmit is cheap).\n  Coordinator: the single --mcp node runs the iterate/shuffle loop and merges partials; it is not yet redundant — if it dies mid-run that run is lost, though a fresh submit on a new coordinator is fine (worker datasets and caches persist).\nThese are known edges, not bugs — design around them or split the work.`
}

@ __help_troubleshooting → s {
    ^ `Common errors and what they mean:\n  "no workers found" / "no GPU workers in the cluster" — no eligible worker has joined. Start one with the SAME --token (add --gpu for the CUDA tools) and give discovery a moment; a different token is invisible.\n  "the … kernel did not compile: …" — your CUDA-C or NURL source had an error; the compiler message is included. Fix it and resubmit.\n  "a chunk failed on a worker" — a worker trapped (bad kernel, no GPU, a lost block). Check the kernel and that --gpu workers exist, then resubmit.\n  task stays "running" — keep polling compute_result; the coordinator advances tasks on each call, and very large ranges simply take longer.\n  dataset range errors — with "dataset", lo/hi must lie within [0, count); omit them to use the whole dataset.\n  HTTPS / cert — the server self-signs on first run; trust the cert or use curl -k. The endpoint path is /mcp.\n  "may not contain a backtick character" — CUDA and NURL kernel sources cannot contain a backtick.`
}

@ tool_help Json args → Json {
    : s topic ?? ( json_obj_get args `topic` ) { T x → ( json_str_data x ) F → `` }
    ? != ( nurl_str_eq topic `overview` ) 0 { ^ ( mcp_tool_result_text ( __help_overview ) ) } {}
    ? != ( nurl_str_eq topic `workflow` ) 0 { ^ ( mcp_tool_result_text ( __help_workflow ) ) } {}
    ? != ( nurl_str_eq topic `expr` ) 0 { ^ ( mcp_tool_result_text ( __help_expr ) ) } {}
    ? != ( nurl_str_eq topic `cuda` ) 0 { ^ ( mcp_tool_result_text ( __help_cuda ) ) } {}
    ? != ( nurl_str_eq topic `iterate` ) 0 { ^ ( mcp_tool_result_text ( __help_iterate ) ) } {}
    ? != ( nurl_str_eq topic `shuffle` ) 0 { ^ ( mcp_tool_result_text ( __help_shuffle ) ) } {}
    ? != ( nurl_str_eq topic `datasets` ) 0 { ^ ( mcp_tool_result_text ( __help_datasets ) ) } {}
    ? != ( nurl_str_eq topic `gpu` ) 0 { ^ ( mcp_tool_result_text ( __help_gpu ) ) } {}
    ? != ( nurl_str_eq topic `limits` ) 0 { ^ ( mcp_tool_result_text ( __help_limits ) ) } {}
    ? != ( nurl_str_eq topic `troubleshooting` ) 0 { ^ ( mcp_tool_result_text ( __help_troubleshooting ) ) } {}
    ^ ( mcp_tool_result_text ( __help_index ) )
}

@ ms_schema_help → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( ms_prop props `topic` `string` `One of: overview, workflow, expr, cuda, iterate, shuffle, datasets, gpu, limits, troubleshooting. Omit to get the topic index.` )
    ( json_obj_set schema `properties` props )
    ^ schema
}

@ build_tools_list → ( Vec Json ) {
    : ( Vec Json ) tools ( vec_new [Json] )
    ( vec_push [Json] tools ( mcp_tool_descriptor `swarm_help`
    `Guidance for using this server, one topic at a time — the tool schemas are kept short, so call this for depth: the CUDA-C ABI, the compute_iterate and compute_shuffle recipes, dataset caching, and the honest size/support limits. Pass a "topic" (overview, workflow, expr, cuda, iterate, shuffle, datasets, gpu, limits, troubleshooting) or omit it for the index. Start here if unsure how a tool works.`
    ( ms_schema_help ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_submit`
    `Distributed map-reduce over an integer/float EXPRESSION in x across [lo, hi): evaluate the kernel per x, fold with reduce (sum/product/min/max/count). Returns a task_id; poll compute_result. E.g. {"expr":"x*x","lo":1,"hi":1000000,"reduce":"sum"}. Grammar, dtype and examples: swarm_help "expr".`
    ( ms_schema_submit ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_submit_kernel`
    `Run an arbitrary NURL kernel for what the expression language can't express (loops, helpers). Give just the per-element kernel as NURL source (@ kernel i x → i { … }); the server wraps it, compiles to wasm, shards it, and folds kernel(x) over [lo, hi) with reduce. Compile errors are returned. Returns a task_id; poll compute_result. Already-compiled module: compute_run_wasm.`
    ( ms_schema_submit_kernel ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_submit_cuda`
    `Distributed GPU map-reduce — write only a CUDA-C __device__ double f(long long x); the server generates the whole GPU program and the --gpu workers run it, folding f(x) over [lo, hi) with reduce (a float). For heavy numeric ranges, millions to billions of x: integrals, Monte-Carlo sums, parameter scans. Needs a --gpu worker; returns a task_id, poll compute_result. CUDA ABI, params and datasets: swarm_help "cuda".`
    ( ms_schema_submit_cuda ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_sample_cuda`
    `Distributed GPU map that returns EVERY value in order — sample a curve, render a field, tabulate a function. CUDA-C f(x) over [lo, hi); results inline (JSON ≤ 1024, base64 ≤ 65536) or to out_file (≤ 1M); min/max/mean included. Needs a --gpu worker; returns a task_id, poll compute_result. ABI & params: swarm_help "cuda".`
    ( ms_schema_sample_cuda ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_histogram_cuda`
    `Distributed GPU binned aggregation in ONE pass: CUDA-C bin(x) picks one of K buckets, val(x) (default 1.0) is added — value distributions, densities, class counts, binned integrals. K bin sums come back (JSON ≤ 1024, base64 ≤ 65536, out_file beyond). Needs a --gpu worker; returns a task_id, poll compute_result. ABI & params: swarm_help "cuda".`
    ( ms_schema_hist_cuda ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_iterate`
    `Iterative solver with the loop IN THE ENGINE — one call returns the converged "state". Each round reduces a CUDA grad() into an accumulator, then applies a step rule. DEFAULT is gradient descent (give "lr", state[j] -= lr*grad[j]/N); for k-means, EM, power iteration, PageRank, momentum/Adam give an "update" device function (and "acc_dim" when the accumulator is wider than the state). Over a dataset the data caches after round one. Needs a --gpu worker. Recipes and the swarm_state/swarm_acc/swarm_N accessors: swarm_help "iterate".`
    ( ms_schema_iterate ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_shuffle`
    `Group-by-key / reduce-by-key. A CUDA key(x)+value(x) map plus a reduce op; both the map AND the per-key reduce run distributed on the GPU (a combiner), and the coordinator merges compact per-chunk tables. Returns { "groups": {…}, "n_groups", "pairs_mapped" }. Word-count, keyed histograms, joins. hi - lo ≤ 8388608, ≤ 65536 distinct keys. Needs a --gpu worker. Details: swarm_help "shuffle".`
    ( ms_schema_shuffle ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_upload_data`
    `Upload a dataset (flat f64 array) the GPU tools map over: {"data_base64": raw little-endian f64} or {"file": path on the MCP host}, ≤ 256 MiB. Returns {dataset_id, count, min, max, mean}. Then pass "dataset":id to the CUDA tools — device functions receive double v = data[x]. Cut into content-addressed 1 MiB blocks cached per worker, so the data moves ONCE (seeded_blocks reports blocks moved). Details: swarm_help "datasets".`
    ( ms_schema_upload_data ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_list_data`
    `List every uploaded dataset: id, name, element count.`
    ( ms_schema_empty ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_run_wasm`
    `Like compute_submit_kernel but you provide an already-compiled wasm32-wasi module (base64) instead of NURL source — e.g. one built with the nurl_build_wasm tool. The module's main reads lo and hi from argv, folds the kernel over [lo, hi), and prints the partial. Returns a task_id; poll compute_result.`
    ( ms_schema_run_wasm ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_list`
    `List every submitted task with its status (running|done), kernel, range, reduce op, and result if finished.`
    ( ms_schema_empty ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_result`
    `Get one task by task_id: its status and, once finished, the reduced result.`
    ( ms_schema_result ) ) )
    ^ tools
}

@ dispatch_tool s name Json args → Json {
    ? != ( nurl_str_eq name `swarm_help` ) 0 { ^ ( tool_help args ) } {}
    ? != ( nurl_str_eq name `compute_submit` ) 0 { ^ ( tool_submit args ) } {}
    ? != ( nurl_str_eq name `compute_submit_kernel` ) 0 { ^ ( tool_submit_kernel args ) } {}
    ? != ( nurl_str_eq name `compute_submit_cuda` ) 0 { ^ ( tool_submit_cuda args ) } {}
    ? != ( nurl_str_eq name `compute_iterate` ) 0 { ^ ( tool_iterate args ) } {}
    ? != ( nurl_str_eq name `compute_shuffle` ) 0 { ^ ( tool_shuffle args ) } {}
    ? != ( nurl_str_eq name `compute_sample_cuda` ) 0 { ^ ( tool_sample_cuda args ) } {}
    ? != ( nurl_str_eq name `compute_histogram_cuda` ) 0 { ^ ( tool_hist_cuda args ) } {}
    ? != ( nurl_str_eq name `compute_upload_data` ) 0 { ^ ( tool_upload_data args ) } {}
    ? != ( nurl_str_eq name `compute_list_data` ) 0 { ^ ( tool_list_data args ) } {}
    ? != ( nurl_str_eq name `compute_run_wasm` ) 0 { ^ ( tool_run_wasm args ) } {}
    ? != ( nurl_str_eq name `compute_list` ) 0 { ^ ( tool_list args ) } {}
    ? != ( nurl_str_eq name `compute_result` ) 0 { ^ ( tool_result args ) } {}
    ^ ( mcp_tool_result_error `unknown tool` )
}

// ── JSON-RPC method handlers ─────────────────────────────────────

@ handle_initialize Json id → Json {
    : Json result ( mcp_initialize_result `swarm-mcp` `0.15.0` )
    ^ ( mcp_response_result id result )
}

@ handle_ping Json id → Json {
    : Json empty ( json_obj_new )
    ^ ( mcp_response_result id empty )
}

@ handle_tools_list Json id → Json {
    : ( Vec Json ) tools ( build_tools_list )
    : Json result ( mcp_tools_list_result tools )
    ^ ( mcp_response_result id result )
}

@ handle_tools_call Json id Json params → Json {
    : ?Json name_j ( json_obj_get params `name` )
    ?? name_j {
        T nv → {
            : s name ( json_str_data nv )
            : Json args ?? ( json_obj_get params `arguments` ) { T av → ( json_clone av ) F → ( json_obj_new ) }
            : Json result ( dispatch_tool name args )
            ( json_free args )
            ^ ( mcp_response_result id result )
        }
        F → { ^ ( mcp_response_error id mcp_err_invalid_params `tools/call requires a "name"` ) }
    }
}

@ handle_unknown Json id s method → Json {
    : i mlen ( nurl_str_len method )
    : String msg ( string_with_cap + 20 mlen )
    ( string_push_str msg `unknown method: ` )
    ( string_push_str msg method )
    : Json err ( mcp_response_error id mcp_err_method_not_found ( string_data msg ) )
    ( string_free msg )
    ^ err
}

@ dispatch Json req → ?Json {
    : ?Json method_j ( json_obj_get req `method` )
    ?? method_j {
        T mv → {
            : s method ( json_str_data mv )
            : ?Json id_opt ( json_obj_get req `id` )
            ?? id_opt {
                T id → {
                    ? != ( nurl_str_eq method `initialize` ) 0 { ^ @ ?Json { T ( handle_initialize id ) } } {}
                    ? != ( nurl_str_eq method `ping` ) 0 { ^ @ ?Json { T ( handle_ping id ) } } {}
                    ? != ( nurl_str_eq method `tools/list` ) 0 { ^ @ ?Json { T ( handle_tools_list id ) } } {}
                    ? != ( nurl_str_eq method `tools/call` ) 0 {
                        : Json params ?? ( json_obj_get req `params` ) { T pv → ( json_clone pv ) F → ( json_obj_new ) }
                        : Json out ( handle_tools_call id params )
                        ( json_free params )
                        ^ @ ?Json { T out }
                    } {}
                    ^ @ ?Json { T ( handle_unknown id method ) }
                }
                F → { ^ @ ?Json { F } }
            }
        }
        F → { ^ @ ?Json { F } }
    }
}

// ── MCP role: the LLM control surface over HTTPS JSON-RPC ─────────
// A coordinator (role_client) that submits work to the ring and serves the MCP
// tools over a TLS HTTP/1.1 endpoint (the standard MCP "Streamable HTTP"
// transport). Runs the blocking HTTP server off the reactor on its own thread,
// so a slow TLS handshake never stalls a co-located relay or worker.

// The coordinator's relay endpoints and its current index — the submit path
// rebuilds the swarm against the next relay when the current one dies
// (mcp_ensure_relay below). Held as globals because the MCP handlers are
// top-level functions over module state, like the swarm itself.
: ~ i g_mcp_relays 0  // *( Vec String ) as an address
: ~ i g_mcp_from 0  // next relay index to try
: ~ s g_mcp_token ``
: ~ i g_mcp_reconnects 0

// Build a fresh coordinator swarm on the next reachable relay and swap it
// into the McpState, preserving tasks / datasets / caches. Returns F when no
// relay in the list is reachable. Called from the submit path when the
// current relay looks dead, so a relay failure does not take the API down.
@ mcp_reconnect → b {
    : *McpState st # *McpState g_mcp
    : ( Vec String ) relays # ( Vec String ) g_mcp_relays
    : *u idxc ( nurl_alloc 8 )
    ( nurl_poke idxc 0 0 )
    : ~ b ok F
    ?? ( relay_dial_list relays `127.0.0.1` 47700 g_mcp_from idxc ) {
        T rc → {
            : i cur ( nurl_peek idxc 0 )
            = g_mcp_from % + cur 1 ( vec_len [String] relays )
            : i myid ( rand_u64 )
            : ( Vec u ) reg ( pk_from_id myid )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 150 )
            : *Swarm nsw ( swarm_new rc myid ( role_client ) 0 g_mcp_token )
            ( swarm_join_group nsw )
            ( swarm_discover nsw 6 )
            : *Swarm old # *Swarm . st swarm
            = . st swarm # s nsw
            ( swarm_free old )
            = g_mcp_reconnects + g_mcp_reconnects 1
            = ok T
        }
        F _ → {}
    }
    ( nurl_free idxc )
    ^ ok
}

// Before a submit: if a heartbeat to the current relay fails, the relay is
// gone — reconnect to the next. Returns T once a live relay is in place.
@ mcp_ensure_relay → b {
    : *Swarm sw ( mcp_swarm )
    ? ( swarm_announce_ok sw 0 ) { ^ T } {}
    ^ ( mcp_reconnect )
}

@ node_mcp ( Vec String ) relays s rhost i rport s mcp_host i mcp_port s cert s key s token → v {
    : *u idxc ( nurl_alloc 8 )
    ( nurl_poke idxc 0 0 )
    ?? ( relay_dial_list relays `127.0.0.1` 47700 0 idxc ) {
        T rc → {
            : i cur ( nurl_peek idxc 0 )
            ( nurl_free idxc )
            : i myid ( rand_u64 )
            : ( Vec u ) reg ( pk_from_id myid )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 150 )
            : *Swarm sw ( swarm_new rc myid ( role_client ) 0 token )
            ( swarm_join_group sw )
            ( swarm_discover sw 6 )
            : *McpState st # *McpState ( nurl_alloc Z McpState )
            = . st swarm # s sw
            = . st tasks ( vec_new [s] )
            = . st wcache ( vec_new [s] )
            = . st datasets ( vec_new [s] )
            = . st next_ds 1
            = . st next_id 1
            = . st seeded ( vec_new [String] )
            = g_mcp # i st
            = g_mcp_relays # i relays
            = g_mcp_from % + cur 1 ( vec_len [String] relays )
            = g_mcp_token token
            : ( @ HttpResponse HttpRequest ) handler ( mcp_http_handler \ Json req → ?Json { ^ ( dispatch req ) } )
            ?? ( tcp_listen_tls mcp_host mcp_port cert key ) {
                T lst → {
                    : HttpServer srv ( server_new lst handler )
                    ?? ( server_run srv ) { T _ → {} F e → {} }
                    ( server_stop srv )
                }
                F e → { ( nurl_eprintln `swarm-mcp: MCP HTTPS listener failed to start (check --tls-cert/--tls-key and that the port is free)` ) }
            }
            ( swarm_free # *Swarm . st swarm )
        }
        F e → { ( nurl_free idxc ) ( nurl_eprintln `swarm-mcp: MCP could not reach any relay in the list` ) }
    }
}

// ── CLI: flag parsing ────────────────────────────────────────────

@ arg_int i idx → i {
    : String s ( env_arg idx )
    : i v ( nurl_str_to_int ( string_data s ) )
    ( string_free s )
    ^ v
}

@ arg_eq i idx s lit → b {
    : String s ( env_arg idx )
    : b eq ? != 0 ( nurl_str_eq ( string_data s ) lit ) T F
    ( string_free s )
    ^ eq
}

// True if `name` appears anywhere in argv (a boolean role/verbose flag).
@ has_flag s name → b {
    : i argc ( env_args_count )
    : ~ b found F
    : ~ i i 1
    ~ & ! found < i argc {
        : String a ( env_arg i )
        ? != 0 ( nurl_str_eq ( string_data a ) name ) { = found T } {}
        ( string_free a )
        = i + i 1
    }
    ^ found
}

// The token following `--name` in argv, or a copy of `deflt`. Owned String.
@ flag_val s name s deflt → String {
    : i argc ( env_args_count )
    : ~ String out ( string_from deflt )
    : ~ b done F
    : ~ i i 1
    ~ & ! done < i argc {
        : String a ( env_arg i )
        : b match ? != 0 ( nurl_str_eq ( string_data a ) name ) T F
        ? & match < + i 1 argc {
            ( string_free out )
            = out ( env_arg + i 1 )
            = done T
        } {}
        ( string_free a )
        = i + i 1
    }
    ^ out
}

@ flag_int s name i deflt → i {
    : String v ( flag_val name `` )
    : i out ? > ( string_len v ) 0 ( nurl_str_to_int ( string_data v ) ) deflt
    ( string_free v )
    ^ out
}

: HostPort { String host i port }

// Parse "host:port", "host", ":port", or "" with host/port defaults.
@ parse_hostport String hp s dhost i dport → HostPort {
    : i n ( string_len hp )
    : i ci ( nurl_str_find ( string_data hp ) `:` )
    ? | == n 0 < ci 0 {
        : String h ? == n 0 ( string_from dhost ) ( string_from ( string_data hp ) )
        ^ @ HostPort { h dport }
    } {}
    : String h0 ( string_substr hp 0 ci )
    : String ps ( string_substr hp + ci 1 - n + ci 1 )
    : i p ( nurl_str_to_int ( string_data ps ) )
    ( string_free ps )
    : String h ? == 0 ( string_len h0 ) { ( string_free h0 ) ( string_from dhost ) } { h0 }
    ^ @ HostPort { h ? > p 0 p dport }
}

// Dial the relays in `lst` starting at `from` (wrapping once around the
// whole list), a few quick retries each. Writes the connected index to
// `idx_cell`. Returns the live client or F when every endpoint is down.
@ relay_dial_list ( Vec String ) lst s dhost i dport i from * u idx_cell → !RelayClient NetErr {
    : i n ( vec_len [String] lst )
    : ~ i tried 0
    : ~ ? RelayClient found @ ?RelayClient { F # RelayClient 0 }
    : ~ b more T
    ~ & more < tried n {
        : i i % + from tried n
        ?? ( vec_get [String] lst i ) {
            T seg → {
                : HostPort hp ( parse_hostport seg dhost dport )
                ?? ( relay_dial_retry ( string_data . hp host ) . hp port 3 ) {
                    T rc → { = found @ ?RelayClient { T rc } ( nurl_poke idx_cell 0 i ) = more F }
                    F _ → {}
                }
                ( string_free . hp host )
            }
            F → {}
        }
        = tried + tried 1
    }
    ?? found { T rc → { ^ @ !RelayClient NetErr { T rc } } F → { ^ @ !RelayClient NetErr { F # NetErr NetOther } } }
}

// Directory part of a path (bytes before the last '/'), empty when the
// path has no directory component.
@ __cert_dirname s path → String {
    : i n # i ( nurl_str_len path )
    : ~ i last - 0 1
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get path k ) 47 { = last k } {}
        = k + k 1
    }
    ? < last 0 { ^ ( string_new ) } {}
    : String owned ( string_from path )
    : String dir ( string_substr owned 0 last )
    ( string_free owned )
    ^ dir
}

// Ensure a TLS cert+key exist at the given paths, auto-minting a self-signed
// EC P-256 pair in pure NURL if absent (std/x509_gen.nu — no openssl, no
// subprocess), so `--mcp` works out of the box; pass --tls-cert/--tls-key for
// a real cert. CN + SAN are `localhost` (matching the previous openssl
// invocation minus the IP SAN — MCP clients pin or use --insecure against a
// self-signed cert either way). Returns T once both files exist.
@ ensure_cert s cert_path s key_path → b {
    ? & ( file_exists cert_path ) ( file_exists key_path ) { ^ T } {}
    : String dir ( __cert_dirname cert_path )
    ? > ( string_len dir ) 0 {
        ?? ( dir_create_all ( string_data dir ) ) {
            T → {}
            F e → {}
        }
    } {}
    ( string_free dir )
    : X509SelfSigned c ( x509_selfsigned_p256 `localhost` 3650 )
    : ~ b ok T
    ?? ( write_file key_path ( string_data . c key_pem ) ) {
        T → {}
        F e → { = ok F }
    }
    ?? ( write_file cert_path ( string_data . c cert_pem ) ) {
        T → {}
        F e → { = ok F }
    }
    ( x509_selfsigned_free c )
    ^ & ok & ( file_exists cert_path ) ( file_exists key_path )
}

// ── dev CLI subcommands (manual testing, no MCP) ─────────────────

@ cli_submit → i {
    : i argc ( env_args_count )
    ? < argc 8 { ( nurl_print `usage: swarm-mcp submit <host> <port> <reduce> <lo> <hi> <expr> --token <secret>\n` ) ^ 1 } {}
    : String host ( env_arg 2 )
    : String rs ( env_arg 4 )
    : i op ( reduce_op_of ( string_data rs ) 0 )
    : String es ( env_arg 7 )
    : String tok ( flag_val `--token` ( string_data ( env_var_or `SWARM_MCP_TOKEN` `` ) ) )
    : i rc ( run_submit ( string_data host ) ( arg_int 3 ) op ( arg_int 5 ) ( arg_int 6 ) ( string_data es ) ( string_data tok ) )
    ( string_free host ) ( string_free rs ) ( string_free es ) ( string_free tok )
    ^ rc
}

@ cli_runwasm → i {
    : i argc ( env_args_count )
    ? < argc 8 { ( nurl_print `usage: swarm-mcp runwasm <host> <port> <reduce> <lo> <hi> <module.wasm> --token <secret>\n` ) ^ 1 } {}
    : String host ( env_arg 2 )
    : String rs ( env_arg 4 )
    : i op ( reduce_op_of ( string_data rs ) 0 )
    : String wp ( env_arg 7 )
    : String tok ( flag_val `--token` ( string_data ( env_var_or `SWARM_MCP_TOKEN` `` ) ) )
    : i rc ( run_runwasm ( string_data host ) ( arg_int 3 ) op ( arg_int 5 ) ( arg_int 6 ) ( string_data wp ) ( string_data tok ) )
    ( string_free host ) ( string_free rs ) ( string_free wp ) ( string_free tok )
    ^ rc
}

@ usage → v {
    ( nurl_print `swarm-mcp — a distributed compute cluster driven over MCP (HTTPS JSON-RPC).\n\n` )
    ( nurl_print `Every node runs the same command; roles combine freely:\n` )
    ( nurl_print `  swarm-mcp --token <secret> [--relay] [--worker] [--mcp] [options]\n\n` )
    ( nurl_print `Roles (any combination):\n` )
    ( nurl_print `  --relay              run a rendezvous relay on this node\n` )
    ( nurl_print `  --worker             run compute worker(s) here (runs expression + wasm kernels)\n` )
    ( nurl_print `  --mcp                serve the MCP control surface over HTTPS JSON-RPC\n\n` )
    ( nurl_print `Cluster:\n` )
    ( nurl_print `  --token <secret>     shared cluster secret — same token = same cluster (required)\n` )
    ( nurl_print `  --connect H:P[,H:P]  relay(s) to join when this node has no --relay; any one\n` )
    ( nurl_print `                       bootstraps it, and it fails over to the next if a relay dies\n\n` )
    ( nurl_print `Bind addresses & tuning:\n` )
    ( nurl_print `  --listen HOST:PORT       relay bind        (default 0.0.0.0:47700)\n` )
    ( nurl_print `  --mcp-listen HOST:PORT   MCP HTTPS bind    (default 127.0.0.1:8443)\n` )
    ( nurl_print `  --tls-cert FILE --tls-key FILE  PEM cert+key (default: self-signed in ~/.swarm-mcp)\n` )
    ( nurl_print `  --workers N              worker threads   (default 1)\n` )
    ( nurl_print `  --gpu                    workers run GPU wasm kernels (--allow-gpu; needs the\n` )
    ( nurl_print `                           pure-NURL wasmtime as $WASMTIME + an NVIDIA GPU/CUDA)\n` )
    ( nurl_print `  -v, --verbose\n\n` )
    ( nurl_print `Examples:\n` )
    ( nurl_print `  swarm-mcp --token sekret --relay --worker --mcp              # all-in-one node\n` )
    ( nurl_print `  swarm-mcp --token sekret --worker --connect 10.0.0.1:47700  # join as a worker\n\n` )
    ( nurl_print `MCP tools: compute_submit, compute_submit_kernel, compute_run_wasm, compute_list, compute_result.\n` )
    ( nurl_print `Dev CLI:   swarm-mcp submit|runwasm <host> <port> <reduce> <lo> <hi> <expr|module> --token <secret>\n` )
}

// ── the unified node launcher ────────────────────────────────────
// Parse the role flags and spawn one OS thread per enabled role, each running
// its own blocking event loop and talking over the relay. Block on the threads
// (a node runs until killed).

@ run_node → i {
    : b relay_on ( has_flag `--relay` )
    : b worker_on ( has_flag `--worker` )
    : b mcp_on ( has_flag `--mcp` )
    ? & ! relay_on & ! worker_on ! mcp_on {
        ( nurl_eprintln `swarm-mcp: pick at least one role — --relay, --worker, --mcp (combine freely)` )
        ( usage ) ^ 1
    } {}

    : String tok ( flag_val `--token` ( string_data ( env_var_or `SWARM_MCP_TOKEN` `` ) ) )
    ? & | worker_on mcp_on == 0 ( string_len tok ) {
        ( nurl_eprintln `swarm-mcp: --token <secret> is required (all nodes with the same token form one cluster)` )
        ^ 1
    } {}

    : String ls ( flag_val `--listen` `0.0.0.0:47700` )
    : HostPort lhp ( parse_hostport ls `0.0.0.0` 47700 )
    : String cs ( flag_val `--connect` `` )
    : b have_connect ? > ( string_len cs ) 0 T F
    : HostPort chp ( parse_hostport cs `127.0.0.1` 47700 )
    : String mls ( flag_val `--mcp-listen` `127.0.0.1:8443` )
    : HostPort mhp ( parse_hostport mls `127.0.0.1` 8443 )
    : i vflag ? | ( has_flag `-v` ) ( has_flag `--verbose` ) 1 0
    : i gpuflag ? ( has_flag `--gpu` ) 1 0
    : i nworkers0 ( flag_int `--workers` 1 )
    : i nworkers ? > nworkers0 0 nworkers0 1

    // Where this node's local worker/mcp roles reach the relay. With --relay
    // it is the co-located relay over loopback; otherwise --connect names one
    // or more relays (comma-separated), any of which bootstraps the node and
    // to which the node fails over if its current relay dies.
    ? & | worker_on mcp_on & ! relay_on ! have_connect {
        ( nurl_eprintln `swarm-mcp: --connect HOST[:PORT][,HOST:PORT…] is required for --worker/--mcp when this node has no --relay` )
        ^ 1
    } {}
    : String drh ? relay_on ( string_from `127.0.0.1` ) ( string_from ( string_data . chp host ) )
    : i drp ? relay_on . lhp port . chp port
    : ~ ( Vec String ) relays ( vec_new [String] )
    ? relay_on {
        : String one ( string_new )
        ( string_push_str one `127.0.0.1` )
        ( string_push_char one 58 )
        ( string_push_str one ( nurl_str_int . lhp port ) )
        ( vec_push [String] relays one )
    } {
        ( relay_list_free relays )
        = relays ( parse_relay_list cs `127.0.0.1` 47700 )
    }

    // TLS material for the MCP HTTPS endpoint.
    : String home ( env_var_or `HOME` `/tmp` )
    : String defcert ( string_new ) ( string_push_str defcert ( string_data home ) ) ( string_push_str defcert `/.swarm-mcp/cert.pem` )
    : String defkey ( string_new ) ( string_push_str defkey ( string_data home ) ) ( string_push_str defkey `/.swarm-mcp/key.pem` )
    : String certp ( flag_val `--tls-cert` ( string_data defcert ) )
    : String keyp ( flag_val `--tls-key` ( string_data defkey ) )
    ? mcp_on {
        ? ! ( ensure_cert ( string_data certp ) ( string_data keyp ) ) {
            ( nurl_eprintln `swarm-mcp: no TLS cert/key and could not auto-generate one (is the target directory writable?). Pass --tls-cert FILE --tls-key FILE.` )
            ^ 1
        } {}
    } {}

    // Startup banner.
    ( nurl_print `swarm-mcp node starting — roles:` )
    ? relay_on { ( nurl_print ` relay` ) } {}
    ? worker_on { ( nurl_print ` worker` ) } {}
    ? mcp_on { ( nurl_print ` mcp` ) } {}
    ( nurl_print `\n` )
    ? relay_on { ( nurl_print `  relay   listening ` ) ( nurl_print ( string_data . lhp host ) ) ( nurl_print `:` ) ( nurl_print ( nurl_str_int . lhp port ) ) ( nurl_print `\n` ) } {}
    ? worker_on { ( nurl_print `  worker  x` ) ( nurl_print ( nurl_str_int nworkers ) ) ( nurl_print ? != gpuflag 0 ` (gpu)` `` ) ( nurl_print ` -> ` ) ( nurl_print ( nurl_str_int ( vec_len [String] relays ) ) ) ( nurl_print ` relay(s), first ` ) ( nurl_print ( string_data drh ) ) ( nurl_print `:` ) ( nurl_print ( nurl_str_int drp ) ) ( nurl_print `\n` ) } {}
    ? mcp_on { ( nurl_print `  mcp     https://` ) ( nurl_print ( string_data . mhp host ) ) ( nurl_print `:` ) ( nurl_print ( nurl_str_int . mhp port ) ) ( nurl_print `/  -> relay ` ) ( nurl_print ( string_data drh ) ) ( nurl_print `:` ) ( nurl_print ( nurl_str_int drp ) ) ( nurl_print `\n` ) } {}

    // One closure per role (held alive for the process; worker threads share
    // one closure and each takes a fresh identity inside node_worker).
    : ( @ v ) relay_body \ → v { ( node_relay ( string_data . lhp host ) . lhp port vflag ) }
    : ( @ v ) worker_body \ → v { ( node_worker relays ( string_data drh ) drp ( string_data tok ) vflag gpuflag ) }
    : ( @ v ) mcp_body \ → v { ( node_mcp relays ( string_data drh ) drp ( string_data . mhp host ) . mhp port ( string_data certp ) ( string_data keyp ) ( string_data tok ) ) }

    : ( Vec s ) ths ( vec_new [s] )
    ? relay_on { ?? ( thread_spawn relay_body ) { T t → ( vec_push [s] ths . t raw ) F _ → {} } } {}
    ? worker_on {
        : ~ i wi 0
        ~ < wi nworkers { ?? ( thread_spawn worker_body ) { T t → ( vec_push [s] ths . t raw ) F _ → {} } = wi + wi 1 }
    } {}
    ? mcp_on { ?? ( thread_spawn mcp_body ) { T t → ( vec_push [s] ths . t raw ) F _ → {} } } {}

    : i nth ( vec_len [s] ths )
    ? == nth 0 { ( nurl_eprintln `swarm-mcp: failed to start any role thread` ) ^ 1 } {}
    : ~ i ji 0
    ~ < ji nth {
        : s raw ?? ( vec_get [s] ths ji ) { T x → x F → # s 0 }
        ? != # i raw 0 { ( thread_join @ Thread { raw } ) } {}
        = ji + ji 1
    }
    ^ 0
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 { ( usage ) ^ 1 } {}
    ? ( arg_eq 1 `submit` ) { ^ ( cli_submit ) } {}
    ? ( arg_eq 1 `runwasm` ) { ^ ( cli_runwasm ) } {}
    ? | ( arg_eq 1 `-h` ) | ( arg_eq 1 `--help` ) ( arg_eq 1 `help` ) { ( usage ) ^ 0 } {}
    ^ ( run_node )
}
