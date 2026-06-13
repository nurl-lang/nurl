// examples/cluster_rpc.nu — distributed fan-out / fan-in over the
// stdlib/ext/cluster.nu RPC primitive (Phase 1 MVP of the distributed-
// computing track). Demonstrates the "agentic NURL" shape: scatter a
// batch of tasks across a cluster of worker nodes, gather the results.
//
// This demo distributes a trivial compute (square a number) so it needs
// no API keys and runs anywhere. To turn it into the LLM fan-out demo,
// swap the `square` handler body for a call into `stdlib/ext/anthropic.nu`
// (`claude_messages …`) — the cluster plumbing is identical.
//
// ── Run it (one machine, three terminals) ────────────────────────────
//
//   ./nurl.sh examples/cluster_rpc.nu server 9101
//   ./nurl.sh examples/cluster_rpc.nu server 9102
//   ./nurl.sh examples/cluster_rpc.nu client 9101 9102
//
// The client scatters squares of 1..10 across the worker ports it was
// given (round-robin) and prints the gathered sum — 385.
//
// Worker semantics: at-least-once with retry (see call_remote). Bring a
// worker down mid-run and the client's retries ride over a transient
// blip; kill it for good and you get a ClNet on that task.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/int.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/cluster.nu`

// ── Worker handler ───────────────────────────────────────────────────
//
// Receives a BORROWED args Json (a number), returns an OWNED Json with
// its square. Replace this body with an LLM / DB / GPU call to make the
// cluster do real work.
@ h_square Json args → !Json ClusterErr {
    : ?i ni ( json_num_as_i args )
    ^ ?? ni {
        T n → @ !Json ClusterErr { T ( json_int * n n ) }
        F → @ !Json ClusterErr { F @ ClusterErr { ClSerialize } }
    }
}

@ run_server i port → i {
    : Registry reg ( registry_new )
    ( registry_register reg `square`
    \ Json a → !Json ClusterErr { ^ ( h_square a ) } )

    : String banner ( string_from `worker listening on 127.0.0.1:` )
    ( string_push_int banner port )
    ( string_push_str banner ` (fn: square)\n` )
    ( nurl_print ( string_data banner ) )
    ( string_free banner )

    : !v NetErr sr ( cluster_serve `127.0.0.1` port reg )
    ?? sr {
        T _ → {}
        F e → {
            ( nurl_print `serve error: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
        }
    }
    ( registry_free reg )
    ^ 0
}

// ── Client: scatter 1..10 across the peers, gather the sum ────────────
//
// Each peer gets its own CircuitBreaker (open after 2 consecutive
// failures, 2s cooldown). A dead peer trips its breaker after two slow
// retried failures; every later task routed to it then fails FAST with
// ClCircuitOpen instead of burning the full retry+backoff budget.
@ run_client ( Vec i ) ports → i {
    : i npeers ( vec_len [i] ports )
    ? == npeers 0 {
        ( nurl_print `client: no peer ports given\n` )
        ^ 1
    } {}

    // One breaker per peer.
    : ( Vec CircuitBreaker ) breakers ( vec_new [CircuitBreaker] )
    : ~ i bi 0
    ~ < bi npeers {
        ( vec_push [CircuitBreaker] breakers ( cb_new 2 2000 ) )
        = bi + bi 1
    }
    : RetryPolicy pol ( retry_default )

    : ~ i sum 0
    : ~ i ok 0
    : ~ i task 1
    ~ <= task 10 {
        // round-robin task → peer
        : i pidx % - task 1 npeers
        : i port ?? ( vec_get [i] ports pidx ) { T p → p F → 0 }
        : CircuitBreaker cb ?? ( vec_get [CircuitBreaker] breakers pidx )
        { T c → c F → ( cb_new 1 0 ) }
        : Node n ( node_new `127.0.0.1` port )

        : !Json ClusterErr rr ( call_remote_cb n `square` ( json_int task ) pol cb )
        ?? rr {
            T result → {
                : i v ( json_as_int result )
                ( json_free result )
                = sum + sum v
                = ok + ok 1
                : String line ( string_from `  square(` )
                ( string_push_int line task )
                ( string_push_str line `) = ` )
                ( string_push_int line v )
                ( string_push_str line ` @ :` )
                ( string_push_int line port )
                ( string_push_char line 10 )
                ( nurl_print ( string_data line ) )
                ( string_free line )
            }
            F e → {
                : ClusterErr ce # ClusterErr e
                : String line ( string_from `  task ` )
                ( string_push_int line task )
                ( string_push_str line ` failed: ` )
                ( string_push_str line ( cluster_err_name ce ) )
                ( string_push_char line 10 )
                ( nurl_print ( string_data line ) )
                ( string_free line )
            }
        }
        ( node_free n )
        = task + task 1
    }

    : String summary ( string_from `gathered ` )
    ( string_push_int summary ok )
    ( string_push_str summary `/10 results; sum = ` )
    ( string_push_int summary sum )
    ( string_push_char summary 10 )
    ( nurl_print ( string_data summary ) )
    ( string_free summary )

    ( vec_free_with [CircuitBreaker] breakers
    \ CircuitBreaker c → v { ( cb_free c ) } )
    ^ 0
}

@ usage → i {
    ( nurl_print `usage:\n` )
    ( nurl_print `  cluster_rpc server <port>\n` )
    ( nurl_print `  cluster_rpc client <port> [port ...]\n` )
    ^ 1
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 3 { ^ ( usage ) } {}

    : String mode ( env_arg 1 )
    : s m ( string_data mode )

    : i rc ? != 0 ( nurl_str_eq m `server` ) {
        : String ps ( env_arg 2 )
        : i port ( nurl_str_to_int ( string_data ps ) )
        ( string_free ps )
        ( run_server port )
    } {
        ? != 0 ( nurl_str_eq m `client` ) {
            : ( Vec i ) ports ( vec_new [i] )
            : ~ i k 2
            ~ < k argc {
                : String ps ( env_arg k )
                ( vec_push [i] ports ( nurl_str_to_int ( string_data ps ) ) )
                ( string_free ps )
                = k + k 1
            }
            : i r ( run_client ports )
            ( vec_free [i] ports )
            r
        } {
            ( usage )
        }
    }

    ( string_free mode )
    ^ rc
}
