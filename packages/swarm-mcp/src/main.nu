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
$ `stdlib/std/random.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/job.nu`
$ `stdlib/ext/http_cli.nu`
$ `census.nu`
$ `expr.nu`
$ `work.nu`
$ `wasmkernel.nu`
$ `buildwasm.nu`

@ swarm_vnodes → i { ^ 64 }

@ kind_kernel → i { ^ 1 }

// Fixed 32-byte multicast group (the relay's documented contract).
@ swarm_group_id → ( Vec u ) {
    : ( Vec u ) g ( bytes_from_str `swarmc` )
    ~ < ( vec_len [u] g ) 32 { ( vec_push [u] g # u 0 ) }
    ^ g
}

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
    s roster  // *Roster
    s job  // *JobNode
    ( Vec u ) self_pk
    i self_id
    i role
    ( Vec u ) group
}

@ swarm_new RelayClient rc i id i role → *Swarm {
    : ( Vec u ) me ( pk_from_id id )
    : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
    : *Ring ring ( ring_new )
    : *Roster roster ( roster_new )
    : *JobNode jn ( job_node_new # s tr # s ring me id )
    : *Swarm sw # *Swarm ( nurl_alloc Z Swarm )
    = . sw transport # s tr
    = . sw ring # s ring
    = . sw roster # s roster
    = . sw job # s jn
    = . sw self_pk me
    = . sw self_id id
    = . sw role role
    = . sw group ( swarm_group_id )
    ? == role ( role_worker ) { ( roster_add roster ring me id ( swarm_vnodes ) ) } {}
    ^ sw
}

@ swarm_free * Swarm sw → v {
    ( job_node_free # *JobNode . sw job )
    ( ring_free # *Ring . sw ring )
    ( roster_free # *Roster . sw roster )
    ( transport_free # *Transport . sw transport )
    ( vec_free [u] . sw self_pk )
    ( vec_free [u] . sw group )
    ( nurl_free # s sw )
}

@ swarm_join_group * Swarm sw → v {
    ?? ( transport_group_join # *Transport . sw transport . sw group ) { T _ → {} F _ → {} }
}

@ swarm_announce * Swarm sw i want → v {
    : ( Vec u ) msg ( hello_build . sw self_id . sw role want . sw self_pk )
    ?? ( transport_broadcast # *Transport . sw transport . sw group msg ) { T _ → {} F _ → {} }
    ( vec_free [u] msg )
}

@ swarm_on_hello * Swarm sw Hello h → v {
    ? == . h role ( role_worker ) {
        ( roster_add # *Roster . sw roster # *Ring . sw ring . h pubkey . h id ( swarm_vnodes ) )
        ( transport_add_peer # *Transport . sw transport . h pubkey )
    } {}
    ? & == . h want 1 ! ( bytes_eq . h pubkey . sw self_pk ) {
        : ( Vec u ) reply ( hello_build . sw self_id . sw role 0 . sw self_pk )
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

// ── relay + worker roles ─────────────────────────────────────────

@ run_relay s host i port i vflag → i {
    ?? ( relay_server_start host port ) {
        T rs → {
            : *RelayServer p # *RelayServer ( nurl_alloc Z RelayServer )
            = . p lst . rs lst
            = . p clients . rs clients
            = . p groups . rs groups
            = . p verbose vflag
            ( nurl_print `swarm-mcp relay listening on ` ) ( nurl_print host )
            ( nurl_print `:` ) ( nurl_print_int port )
            ? == vflag 1 { ( nurl_print ` (verbose)` ) } {}
            ( nurl_print `\n` )
            ( relay_server_run p )
            ( relay_server_free p )
            ^ 0
        }
        F e → { ( nurl_print `swarm-mcp: relay failed to bind\n` ) ^ 1 }
    }
}

@ run_worker s host i port i id i rounds → i {
    ?? ( relay_dial host port ) {
        T rc → {
            : ( Vec u ) reg ( pk_from_id id )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 250 )
            : *Swarm sw ( swarm_new rc id ( role_worker ) )
            ( job_register # *JobNode . sw job ( kind_kernel ) ( kernel_handler ) )
            ( job_register # *JobNode . sw job ( kind_wasm ) ( wasm_handler ) )
            ( swarm_join_group sw )
            ( swarm_announce sw 1 )
            ( nurl_print `swarm-mcp worker ` ) ( nurl_print_int id ) ( nurl_print ` ready\n` )
            : ~ i t 0
            ~ | <= rounds 0 < t rounds { ( swarm_pump sw 200 ) = t + t 1 }
            ( swarm_free sw )
            ( relay_close rc )
            ^ 0
        }
        F e → { ( nurl_print `swarm-mcp: worker could not dial relay\n` ) ^ 1 }
    }
}

// ── shared submit: shard an expr task across the cluster ──────────
// Submits the kernel to the ring and returns the chunk task-ids. `expr` is the
// raw kernel bytes; the caller owns it.

@ cluster_submit * Swarm sw i op i lo i hi ( Vec u ) expr i nchunks → ( Vec i ) {
    : ( Vec s ) chunks ( shard lo hi nchunks )
    : ( Vec i ) tids ( vec_new [i] )
    : ~ i i 0
    ~ < i nchunks {
        : s cp ?? ( vec_get [s] chunks i ) { T x → x F → # s 0 }
        : *Chunk c # *Chunk cp
        : ( Vec u ) key ( chunk_key i )
        : ( Vec u ) payload ( chunk_payload op . c lo . c hi expr )
        ( vec_push [i] tids ( job_submit # *JobNode . sw job ( kind_kernel ) key payload ) )
        ( vec_free [u] key ) ( vec_free [u] payload )
        = i + i 1
    }
    ( shard_free chunks )
    ^ tids
}

// Shard a wasm-kernel task: ship the compiled module + each sub-range to its
// ring owner under kind_wasm. The module bytes ride every chunk (workers cache
// by content hash, so it is written once per worker).
@ cluster_submit_wasm * Swarm sw i lo i hi ( Vec u ) wasm i nchunks → ( Vec i ) {
    : ( Vec s ) chunks ( shard lo hi nchunks )
    : ( Vec i ) tids ( vec_new [i] )
    : ~ i i 0
    ~ < i nchunks {
        : s cp ?? ( vec_get [s] chunks i ) { T x → x F → # s 0 }
        : *Chunk c # *Chunk cp
        : ( Vec u ) key ( chunk_key i )
        : ( Vec u ) payload ( wasm_chunk_payload . c lo . c hi wasm )
        ( vec_push [i] tids ( job_submit # *JobNode . sw job ( kind_wasm ) key payload ) )
        ( vec_free [u] key ) ( vec_free [u] payload )
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

// Combine all chunk results with the reduce op (assumes ready).
@ tids_combine * Swarm sw i op ( Vec i ) tids → i {
    : i n ( vec_len [i] tids )
    : ~ i acc ( red_id op )
    : ~ i k 0
    ~ < k n {
        ?? ( job_await # *JobNode . sw job ?? ( vec_get [i] tids k ) { T x → x F → 0 } ) {
            T r → { = acc ( red_combine op acc ( result_decode r ) ) ( vec_free [u] r ) }
            F → {}
        }
        = k + k 1
    }
    ^ acc
}

@ nchunks_for i nworkers → i { ^ ? > * nworkers 4 256 256 ? > nworkers 0 * nworkers 4 4 }

// ── submit role (manual CLI testing, no MCP) ─────────────────────

@ run_submit s host i port i op i lo i hi s expr → i {
    ?? ( relay_dial host port ) {
        T rc → {
            : i myid ( rand_u64 )
            : ( Vec u ) reg ( pk_from_id myid )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 250 )
            : *Swarm sw ( swarm_new rc myid ( role_client ) )
            ( swarm_join_group sw )
            ( swarm_discover sw 8 )
            : i nworkers ( roster_count # *Roster . sw roster )
            ? == nworkers 0 {
                ( nurl_print `swarm-mcp: no workers found\n` )
                ( swarm_free sw ) ( relay_close rc ) ^ 1
            } {}
            : ( Vec u ) eb ( bytes_from_str expr )
            : i nchunks ( nchunks_for nworkers )
            : ( Vec i ) tids ( cluster_submit sw op lo hi eb nchunks )
            : ~ i rnd 0
            ~ & ! ( tids_ready sw tids ) < rnd 400 { ( swarm_pump sw 200 ) = rnd + rnd 1 }
            : i total ( tids_combine sw op tids )
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

@ run_runwasm s host i port i op i lo i hi s wasmpath → i {
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
                    : *Swarm sw ( swarm_new relc myid ( role_client ) )
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
                        : ( Vec i ) tids ( cluster_submit_wasm sw lo hi wasm nchunks )
                        : ~ i rnd 0
                        ~ & ! ( tids_ready sw tids ) < rnd 600 { ( swarm_pump sw 200 ) = rnd + rnd 1 }
                        : i total ( tids_combine sw op tids )
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
    i lo
    i hi
    i op
    i nchunks
    ( Vec i ) tids
    i done
    i result
}

: McpState {
    s swarm  // *Swarm coordinator
    ( Vec s ) tasks  // *Task
    i next_id
}

// Constructor. The params share the field names (`lo`, `hi`, …); `= . t lo lo`
// is a field store — the field-store/local-shadow miscompile this used to work
// around was fixed in the compiler (NURL v0.10.4).
@ task_new i id ( Vec u ) expr i lo i hi i op i nchunks ( Vec i ) tids → *Task {
    : *Task t # *Task ( nurl_alloc Z Task )
    = . t id id
    = . t expr expr
    = . t lo lo
    = . t hi hi
    = . t op op
    = . t nchunks nchunks
    = . t tids tids
    = . t done 0
    = . t result 0
    ^ t
}

: ~ i g_mcp 0

@ mcp_swarm → *Swarm { : *McpState st # *McpState g_mcp ^ # *Swarm . st swarm }

@ mcp_pump i rounds → v {
    : *Swarm sw ( mcp_swarm )
    : ~ i k 0
    ~ < k rounds { ( swarm_pump sw 150 ) = k + k 1 }
}

// Refresh one task's status; combine if every chunk has landed.
@ task_refresh * Task t → v {
    ? == . t done 1 { ^ v } {}
    : *Swarm sw ( mcp_swarm )
    ? ( tids_ready sw . t tids ) {
        = . t result ( tids_combine sw . t op . t tids )
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
    ( json_obj_set o `status` ( json_str_lit ? == . t done 1 `done` `running` ) )
    : String es ( bytes_to_str . t expr )
    ( json_obj_set o `kernel` ( json_str_lit ( string_data es ) ) )
    ( string_free es )
    ( json_obj_set o `reduce` ( json_str_lit ( reduce_op_name . t op ) ) )
    ( json_obj_set o `lo` ( json_int . t lo ) )
    ( json_obj_set o `hi` ( json_int . t hi ) )
    ( json_obj_set o `chunks` ( json_int . t nchunks ) )
    ? == . t done 1 { ( json_obj_set o `result` ( json_int . t result ) ) } {}
    ^ o
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
    : *Swarm sw ( mcp_swarm )
    ( swarm_discover sw 6 )
    : i nworkers ( roster_count # *Roster . sw roster )
    ? == nworkers 0 {
        ( vec_free [u] eb )
        ^ ( mcp_tool_result_error `no workers in the cluster — start some with 'swarm-mcp worker'` )
    } {}
    : i nchunks ( nchunks_for nworkers )
    : ( Vec i ) tids ( cluster_submit sw op lo hi eb nchunks )

    : *McpState st # *McpState g_mcp
    : *Task t ( task_new . st next_id eb lo hi op nchunks tids )
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

@ __ship_wasm ( Vec u ) wasm i lo i hi i op → Json {
    ? == ( vec_len [u] wasm ) 0 { ( vec_free [u] wasm ) ^ ( mcp_tool_result_error `empty wasm module` ) } {}
    : *Swarm sw ( mcp_swarm )
    ( swarm_discover sw 6 )
    : i nworkers ( roster_count # *Roster . sw roster )
    ? == nworkers 0 {
        ( vec_free [u] wasm )
        ^ ( mcp_tool_result_error `no workers in the cluster — start some with 'swarm-mcp worker'` )
    } {}
    : i nchunks ( nchunks_wasm nworkers )
    : ( Vec i ) tids ( cluster_submit_wasm sw lo hi wasm nchunks )
    ( vec_free [u] wasm )
    : *McpState st # *McpState g_mcp
    : *Task t ( task_new . st next_id ( bytes_from_str `<wasm kernel>` ) lo hi op nchunks tids )
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
    ? >= lo hi { ^ ( mcp_tool_result_error `empty range: need lo < hi` ) } {}
    : !( Vec u ) ParseErr dr ( b64_decode_vec w64 )
    ?? dr {
        F e → { ^ ( mcp_tool_result_error `wasm_base64 is not valid base64` ) }
        T wasm → { ^ ( __ship_wasm wasm lo hi op ) }
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
    ? >= lo hi { ^ ( mcp_tool_result_error `empty range: need lo < hi` ) } {}
    // Wrap the bare kernel (`@ kernel i x → i`) into a full program: a main that
    // reads lo/hi from argv and folds kernel(x) over the range with the op.
    : String wrapped ( wrap_kernel source op )
    : !( Vec u ) String cr ( compile_to_wasm ( string_data wrapped ) )
    ( string_free wrapped )
    ?? cr {
        F msg → {
            : String em ( string_concat ( string_from `kernel did not compile: ` ) msg )
            : Json e ( mcp_tool_result_error ( string_data em ) )
            ( string_free em ) ( string_free msg )
            ^ e
        }
        T wasm → { ^ ( __ship_wasm wasm lo hi op ) }
    }
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
    ( ms_prop props `expr` `string` `Kernel: an integer expression in the variable x. Operators + - * / % (truncated div), comparisons < <= > >= == != (yield 0/1), logical & | , ternary cond ? a : b ; functions min(a,b) max(a,b) abs(a). Examples: "x*x" · "x%2==0" · "x>1 & x<100" · "x>5 ? x : 0".` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `reduce` `string` `How to fold the mapped values across the whole range: "sum" (default) · "product" · "min" · "max" · "count" (how many x make the kernel non-zero).` )
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
    ( ms_prop props `wasm_base64` `string` `A base64-encoded wasm32-wasi module — the compiled kernel. Build it from NURL with the nurl_build_wasm tool. The module's main must read two integers lo and hi from argv, fold your kernel over x in [lo, hi), and print the partial result as a decimal integer to stdout. The cluster shards [lo, hi), runs the module on each worker with its sub-range, and combines the partials with the reduce op.` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `reduce` `string` `How to combine the per-worker partials: "sum" (default), "product", "min", "max", or "count". Must match what the module's main reduces with.` )
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
    ( ms_prop props `source` `string` `NURL source defining a per-element kernel: @ kernel i x → i { … } — it takes one integer x and returns one integer. You may also import stdlib and define helper functions; do NOT define main (the server generates it). The cluster evaluates kernel(x) for every x in [lo, hi) and folds the results with the reduce op. Example (counts primes): @ is_prime i n → b { … }  @ kernel i x → i { ? ( is_prime x ) 1 0 }. The server compiles this to wasm and runs it sharded across the workers.` )
    ( ms_prop props `lo` `integer` `Range start (inclusive).` )
    ( ms_prop props `hi` `integer` `Range end (exclusive). Must be > lo.` )
    ( ms_prop props `reduce` `string` `How to combine the per-worker partials: "sum" (default), "product", "min", "max", or "count". Must match what your main reduces with.` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `source` ) )
    ( json_arr_push req ( json_str_lit `lo` ) )
    ( json_arr_push req ( json_str_lit `hi` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ build_tools_list → ( Vec Json ) {
    : ( Vec Json ) tools ( vec_new [Json] )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_submit`
    `Run a distributed map-reduce on the cluster: evaluate the expression kernel for every integer x in [lo, hi) and fold the results with the reduce op. Sharded across all live workers and computed in parallel. Returns a task_id immediately; poll compute_result for the value. Example: {"expr":"x*x","lo":1,"hi":1000000,"reduce":"sum"} gives the sum of squares.`
    ( ms_schema_submit ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `compute_submit_kernel`
    `Run an arbitrary NURL kernel on the cluster for workloads the compute_submit expression language cannot express (loops, helper functions, anything). Provide just the per-element kernel as NURL source — @ kernel i x → i { … } plus any imports/helpers; no main needed, the server generates the argv-reading, fold, and print boilerplate. The server compiles the wrapped program to wasm itself (via the NURL build service) and runs it sharded across the workers, folding kernel(x) over [lo, hi) with the reduce op. Compile errors are returned to you. Returns a task_id; poll compute_result. (Use compute_run_wasm if you already have a compiled module.)`
    ( ms_schema_submit_kernel ) ) )
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
    ? != ( nurl_str_eq name `compute_submit` ) 0 { ^ ( tool_submit args ) } {}
    ? != ( nurl_str_eq name `compute_submit_kernel` ) 0 { ^ ( tool_submit_kernel args ) } {}
    ? != ( nurl_str_eq name `compute_run_wasm` ) 0 { ^ ( tool_run_wasm args ) } {}
    ? != ( nurl_str_eq name `compute_list` ) 0 { ^ ( tool_list args ) } {}
    ? != ( nurl_str_eq name `compute_result` ) 0 { ^ ( tool_result args ) } {}
    ^ ( mcp_tool_result_error `unknown tool` )
}

// ── JSON-RPC method handlers ─────────────────────────────────────

@ handle_initialize Json id → Json {
    : Json result ( mcp_initialize_result `swarm-mcp` `0.1.0` )
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

@ stdio_loop → v {
    : ~ b running T
    ~ running {
        : ?Json msg ( mcp_read_request )
        ?? msg {
            T req → {
                : ?Json reply ( dispatch req )
                ( json_free req )
                ?? reply {
                    T resp → ( mcp_send_message resp )
                    F empty → {}
                }
            }
            F → { = running F }
        }
    }
}

@ run_mcp s host i port → i {
    ?? ( relay_dial host port ) {
        T rc → {
            : i myid ( rand_u64 )
            : ( Vec u ) reg ( pk_from_id myid )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 150 )
            : *Swarm sw ( swarm_new rc myid ( role_client ) )
            ( swarm_join_group sw )
            ( swarm_discover sw 6 )
            : *McpState st # *McpState ( nurl_alloc Z McpState )
            = . st swarm # s sw
            = . st tasks ( vec_new [s] )
            = . st next_id 1
            = g_mcp # i st
            ( mcp_log `swarm-mcp ready (cluster coordinator over relay)` )
            ( stdio_loop )
            ( swarm_free sw )
            ( relay_close rc )
            ^ 0
        }
        F e → { ( nurl_eprintln `swarm-mcp: mcp could not dial relay` ) ^ 1 }
    }
}

// ── CLI ──────────────────────────────────────────────────────────

@ usage → v {
    ( nurl_print `swarm-mcp — MCP-controlled distributed compute engine\n\n` )
    ( nurl_print `  swarm-mcp relay  <host> <port> [--v]\n` )
    ( nurl_print `  swarm-mcp worker <host> <port> [id] [rounds]\n` )
    ( nurl_print `  swarm-mcp mcp    <host> <port>            (MCP server over stdio)\n` )
    ( nurl_print `  swarm-mcp submit  <host> <port> <reduce> <lo> <hi> <expr>\n` )
    ( nurl_print `  swarm-mcp runwasm <host> <port> <reduce> <lo> <hi> <module.wasm>\n\n` )
    ( nurl_print `MCP tools: compute_submit (expression kernel), compute_run_wasm (NURL→wasm\n` )
    ( nurl_print `kernel), compute_list, compute_result. reduce = sum|product|min|max|count.\n` )
}

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

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 { ( usage ) ^ 1 } {}
    : ~ i rc 0
    ? ( arg_eq 1 `relay` ) {
        ? < argc 4 { ( nurl_print `usage: swarm-mcp relay <host> <port> [--v]\n` ) = rc 1 } {
            : String host ( env_arg 2 )
            : i vflag ? & > argc 5 ( arg_eq 4 `--v` ) 1 ? & > argc 5 ( arg_eq 4 `--verbose` ) 1 0
            = rc ( run_relay ( string_data host ) ( arg_int 3 ) vflag )
            ( string_free host )
        }
    } {
        ? ( arg_eq 1 `worker` ) {
            ? < argc 4 { ( nurl_print `usage: swarm-mcp worker <host> <port> [id] [rounds]\n` ) = rc 1 } {
                : String host ( env_arg 2 )
                : i id ? > argc 4 ( arg_int 4 ) ( rand_u64 )
                : i rounds ? > argc 5 ( arg_int 5 ) 0
                = rc ( run_worker ( string_data host ) ( arg_int 3 ) id rounds )
                ( string_free host )
            }
        } {
            ? ( arg_eq 1 `mcp` ) {
                ? < argc 4 { ( nurl_print `usage: swarm-mcp mcp <host> <port>\n` ) = rc 1 } {
                    : String host ( env_arg 2 )
                    = rc ( run_mcp ( string_data host ) ( arg_int 3 ) )
                    ( string_free host )
                }
            } {
                ? ( arg_eq 1 `submit` ) {
                    ? < argc 8 { ( nurl_print `usage: swarm-mcp submit <host> <port> <reduce> <lo> <hi> <expr>\n` ) = rc 1 } {
                        : String host ( env_arg 2 )
                        : String rs ( env_arg 4 )
                        : i op ( reduce_op_of ( string_data rs ) 0 )
                        : String es ( env_arg 7 )
                        = rc ( run_submit ( string_data host ) ( arg_int 3 ) op ( arg_int 5 ) ( arg_int 6 ) ( string_data es ) )
                        ( string_free host ) ( string_free rs ) ( string_free es )
                    }
                } {
                    ? ( arg_eq 1 `runwasm` ) {
                        ? < argc 8 { ( nurl_print `usage: swarm-mcp runwasm <host> <port> <reduce> <lo> <hi> <module.wasm>\n` ) = rc 1 } {
                            : String host ( env_arg 2 )
                            : String rs ( env_arg 4 )
                            : i op ( reduce_op_of ( string_data rs ) 0 )
                            : String wp ( env_arg 7 )
                            = rc ( run_runwasm ( string_data host ) ( arg_int 3 ) op ( arg_int 5 ) ( arg_int 6 ) ( string_data wp ) )
                            ( string_free host ) ( string_free rs ) ( string_free wp )
                        }
                    } {
                        ( usage ) = rc 1
                    }
                }
            }
        }
    }
    ^ rc
}
