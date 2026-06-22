// examples/dchannel.nu — distributed Channel[A] producer/consumer across
// processes (TODO §7.2). The producer SENDS integers on a channel hosted
// on another process; the consumer RECEIVES them and sums. The values
// move out of the producer's address space and into the consumer's —
// the same send/recv shape you'd write for a local std/channel.nu Channel.
//
// The hosted channel "nums" has capacity 4, so a producer that outruns a
// slow consumer BLOCKS on send until space frees up (end-to-end
// backpressure) — exactly like a bounded local channel.
//
// ── Run it (one machine, three terminals) ────────────────────────────
//
//   ./nurl.sh examples/dchannel.nu server  9400
//   ./nurl.sh examples/dchannel.nu consume 9400
//   ./nurl.sh examples/dchannel.nu produce 9400 10
//
// The producer sends 1..10 then closes; the consumer drains them, prints
// each, and reports the sum (55). To make it a distributed channel of
// your own type A, swap the three int codecs below for A↔Json closures.

$ `stdlib/core/string.nu`
$ `stdlib/std/int.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/cluster.nu`
$ `stdlib/ext/dchannel.nu`

@ println s text → v { ( nurl_print text ) ( nurl_print `\n` ) }

@ print_kv s label i n → v {
    : String line ( string_from label )
    ( string_push_int line n )
    ( string_push_char line 10 )
    ( nurl_print ( string_data line ) )
    ( string_free line )
}

// Open the shared "nums" channel of i (int) with JSON int codecs.
@ open_int_chan i port → ( DChannel i ) {
    : Node node ( node_new `127.0.0.1` port )
    ^ ( dchan_open [i] node `nums` ( retry_default ) 20
    \ i x → Json { ^ ( json_int x ) }  // enc: i → Json
    \ Json j → i { ^ ( json_as_int j ) }  // dec: Json → i
    \ i x → v {} )  // drop: scalar, no-op
}

// ── Server: host the bounded channel ─────────────────────────────────
@ run_server i port → i {
    : DStore store ( dstore_new 8 )
    ( dstore_declare store `nums` 4 )  // capacity 4 → backpressure
    : String banner ( string_from `dchannel server on 127.0.0.1:` )
    ( string_push_int banner port )
    ( string_push_str banner ` (channel "nums", cap 4)\n` )
    ( nurl_print ( string_data banner ) )
    ( string_free banner )

    : !v NetErr sr ( dchan_serve `127.0.0.1` port store )
    ?? sr {
        T _ → {}
        F e → ( println `serve error: ` )
    }
    ( dstore_free store )
    ^ 0
}

// ── Producer: send 1..n, then close ──────────────────────────────────
@ run_produce i port i n → i {
    : ( DChannel i ) ch ( open_int_chan port )
    : ~ i k 1
    ~ <= k n {
        : b okk ( dchan_send [i] ch k )
        ? okk { ( print_kv `  sent ` k ) }
        { ( print_kv `  send failed (closed) at ` k ) }
        = k + k 1
    }
    ( dchan_close [i] ch )
    ( println `producer done; channel closed` )
    ( dchan_free [i] ch )
    ^ 0
}

// ── Consumer: recv until the channel is closed AND drained ────────────
@ run_consume i port → i {
    : ( DChannel i ) ch ( open_int_chan port )
    : ~ i sum 0
    : ~ i cnt 0
    : ~ b done F
    ~ ! done {
        : ?i got ( dchan_recv [i] ch )
        ?? got {
            T v → {
                = sum + sum v
                = cnt + cnt 1
                ( print_kv `  recv ` v )
            }
            F → { = done T }
        }
    }
    : String line ( string_from `consumed ` )
    ( string_push_int line cnt )
    ( string_push_str line ` items; sum = ` )
    ( string_push_int line sum )
    ( string_push_char line 10 )
    ( nurl_print ( string_data line ) )
    ( string_free line )
    ( dchan_free [i] ch )
    ^ 0
}

@ usage → i {
    ( println `usage:` )
    ( println `  dchannel server  <port>` )
    ( println `  dchannel produce <port> <n>` )
    ( println `  dchannel consume <port>` )
    ^ 1
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 3 { ^ ( usage ) } {}

    : String mode ( env_arg 1 )
    : s m ( string_data mode )
    : String ps ( env_arg 2 )
    : i port ( nurl_str_to_int ( string_data ps ) )
    ( string_free ps )

    : i rc ? != 0 ( nurl_str_eq m `server` ) {
        ( run_server port )
    } {
        ? != 0 ( nurl_str_eq m `produce` ) {
            ? < argc 4 { ( usage ) } {
                : String ns ( env_arg 3 )
                : i n ( nurl_str_to_int ( string_data ns ) )
                ( string_free ns )
                ( run_produce port n )
            }
        } {
            ? != 0 ( nurl_str_eq m `consume` ) {
                ( run_consume port )
            } {
                ( usage )
            }
        }
    }

    ( string_free mode )
    ^ rc
}
