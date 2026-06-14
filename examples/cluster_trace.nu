// examples/cluster_trace.nu — distributed trace-id propagation (TODO §7.2).
//
// The server registers `trace_echo`, a handler that returns the trace id
// it is CURRENTLY running under — i.e. the id the client put in the
// outgoing W3C `traceparent` header. The client starts a trace, calls the
// server, and checks the id it gets back equals its own: proof the trace
// propagated across the hop (the basis for correlating logs across a
// fan-out without a central collector).
//
//   ./nurl.sh examples/cluster_trace.nu server 9700
//   ./nurl.sh examples/cluster_trace.nu client 9700

$ `stdlib/core/string.nu`
$ `stdlib/std/async.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/trace.nu`
$ `stdlib/ext/cluster.nu`

@ run_server i port → i {
    : Registry reg ( registry_new )
    // Echo back the trace id this handler runs under (set from the
    // incoming traceparent by registry_handler).
    ( registry_register reg `trace_echo`
    \ Json a → !Json ClusterErr { ^ @ !Json ClusterErr { T ( json_int ( trace_current_trace ) ) } } )
    ( nurl_print `trace server on 127.0.0.1:` ) ( nurl_print_int port ) ( nurl_print `\n` )
    : !v NetErr sr ( cluster_serve `127.0.0.1` port reg )
    ?? sr { T _ → {} F _ → {} }
    ( registry_free reg )
    ^ 0
}

@ run_client i port → i {
    ( trace_start )
    : i mine ( trace_current_trace )
    : String mh ( trace_hex16 mine )
    ( nurl_print `client trace = ` ) ( nurl_print ( string_data mh ) ) ( nurl_print `\n` )
    ( string_free mh )

    : Node n ( node_new `127.0.0.1` port )
    : !Json ClusterErr r ( call_remote n `trace_echo` ( json_null ) )
    : i rc ?? r {
        T res → {
            : i seen ( json_as_int res )
            ( json_free res )
            : String sh ( trace_hex16 seen )
            ( nurl_print `server saw  = ` ) ( nurl_print ( string_data sh ) ) ( nurl_print `\n` )
            ( string_free sh )
            ( nurl_print `propagated: ` )
            ( nurl_print ? == seen mine `YES\n` `NO\n` )
            0
        }
        F e → { ( nurl_print `call failed\n` ) 1 }
    }
    ( node_free n )
    ^ rc
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 3 { ( nurl_print `usage: cluster_trace server|client <port>\n` ) ^ 1 } {}
    : String mode ( env_arg 1 )
    : String ps ( env_arg 2 )
    : i port ( nurl_str_to_int ( string_data ps ) )
    ( string_free ps )
    : i rc ? != 0 ( nurl_str_eq ( string_data mode ) `server` )
    ( run_server port )
    ( run_client port )
    ( string_free mode )
    ^ rc
}
