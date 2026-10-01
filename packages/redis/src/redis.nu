// packages/redis/src/redis.nu — a pure-NURL Redis client. Speaks RESP2 over
// a plain libc TCP socket, or over the pure-NURL TLS client (rediss://) with
// no OpenSSL on the target. The RESP wire format lives in resp.nu; this file
// owns the connection, the request/reply round-trip and an ergonomic command
// surface (GET / SET / INCR / lists / hashes / sets / pub-sub …).
//
//   ( redis_connect host port )                  → !RedisConn RedisErr
//   ( redis_connect_tls host port sni verify )    → !RedisConn RedisErr
//   ( redis_auth conn user password )             → !v RedisErr
//   ( redis_command conn args )                   → !RedisReply RedisErr   (raw)
//   ( redis_get conn key ) / ( redis_set … ) …    → typed helpers
//   ( redis_close conn )                          → v   early release (optional)
//
// Build arbitrary commands with the arg builder:
//   : ( Vec String ) a ( redis_args )
//   ( redis_arg a `SET` ) ( redis_arg a key ) ( redis_arg a val )
//   : !RedisReply RedisErr r ( redis_command c a )
//
// A RedisConn is a handle: every copy is the same connection, and the last
// owner closes it (the TLS session or the socket). Replies, strings,
// messages and argument vectors are plain values. Nothing here is released
// by hand; the *_free functions and redis_close are optional early releases.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/tls.nu`
$ `resp.nu`
$ `stdlib/core/rcbox.nu`

: | RedisErr {
    RedisConnFail  // could not open the TCP socket
    RedisTls  // TLS upgrade failed (handshake / cert error)
    RedisProtocol  // malformed RESP from the server
    RedisIo  // socket read/write failure or unexpected EOF
    RedisServerError  // server returned a RESP error — see redis_last_error
    RedisType  // reply was not the type the helper expected
}

@ redis_err_name RedisErr e → s {
    ^ ?? e {
        RedisConnFail → `RedisConnFail`
        RedisTls → `RedisTls`
        RedisProtocol → `RedisProtocol`
        RedisIo → `RedisIo`
        RedisServerError → `RedisServerError`
        RedisType → `RedisType`
    }
}

// Optional bulk-string reply. found == 0 means the server answered nil
// (e.g. GET on a missing key); `val` is owned and empty in that case.
// A named struct rather than `?String` so it round-trips through `!T E`.
: RedisStr {
    i found
    String val
}

@ redis_str_is_nil RedisStr s → b { ^ == . s found 0 }

@ redis_str_val RedisStr s → s { ^ ( string_data . s val ) }

// Let go of `s` now rather than at the end of its owner's scope.
@ redis_str_free sink RedisStr s → v {}

// A pub/sub frame. kind: 0 message · 1 subscribe · 2 unsubscribe ·
// 3 pmessage · 4 psubscribe · 5 punsubscribe · -1 unrecognised.
// `pattern` is set only for the p* variants; `count` is the live
// subscription count carried by (un)subscribe confirmations.
: RedisMessage {
    i kind
    String channel
    String pattern
    String payload
    i count
}

@ redis_message_kind RedisMessage m → i { ^ . m kind }

@ redis_message_channel RedisMessage m → s { ^ ( string_data . m channel ) }

@ redis_message_pattern RedisMessage m → s { ^ ( string_data . m pattern ) }

@ redis_message_payload RedisMessage m → s { ^ ( string_data . m payload ) }

@ redis_message_count RedisMessage m → i { ^ . m count }
// True for an actual published message (message / pmessage), false for a
// subscribe/unsubscribe control frame.
@ redis_message_is_payload RedisMessage m → b { ^ | == . m kind 0 == . m kind 3 }

// Let go of `m` now rather than at the end of its owner's scope.
@ redis_message_free sink RedisMessage m → v {}

: RedisConnImpl {
    i tls  // 0 plaintext, 1 TLS
    i raw  // raw socket fd (plaintext reads / fd the TLS layer took over)
    TcpConn tcp  // plaintext transport (writes via tcp_write_all)
    * TlsConn tc  // TLS transport (when tls = 1)
    ( Vec u ) rxbuf  // bytes read but not yet parsed into a reply
    String lasterr  // last server error text
    String host_name
    i port_num
    i db_index
}

// The transport is the connection's raw resource: its last owner closes the
// TLS session or the socket, as redis_close did. The buffer and the strings
// go with the drop glue.
% Drop RedisConnImpl { @ drop RedisConnImpl c → v { ( __r_close_transport . c tls . c tc . c raw ) } }

@ __r_close_transport i tls * TlsConn tc i raw → v {
    ? == tls 1 { ( tls_close tc ) } { ( nurl_tcp_close raw ) }
}

: RedisConn { s ctl }

@ RedisConn_share RedisConn h → RedisConn { ^ @ RedisConn { # s ( rcbox_share # i . h ctl ) } }

@ RedisConn_drop sink RedisConn h → v {
    ( mem_forget h )
    ( rcbox_release [RedisConnImpl] # i . h ctl )
}

@ __RedisConn_ptr RedisConn h → *RedisConnImpl { ^ ( rcbox_ptr [RedisConnImpl] # i . h ctl ) }

// ── transport ─────────────────────────────────────────────────────

@ __r_write * RedisConnImpl c ( Vec u ) bytes → i {
    ? == . c tls 1 {
        ?? ( tls_write . c tc bytes ) { T _ → ^ 1 F _ → ^ 0 }
    } {
        ?? ( tcp_write_all . c tcp bytes ) { T _ → ^ 1 F _ → ^ 0 }
    }
}

// Read one chunk into rxbuf. Returns 1 on progress, 0 on EOF/error.
@ __r_fill * RedisConnImpl c → i {
    ? == . c tls 1 {
        ?? ( tls_read . c tc 16384 ) {
            T v → {
                ? == ( vec_len [u] v ) 0 { ^ 0 } {}
                ( __r_cat . c rxbuf v )
                ^ 1
            }
            F _ → ^ 0
        }
    } {
        : ( Vec u ) tmp ( vec_with_cap [u] 16384 )
        : i got ( nurl_tcp_read . c raw # s ( vec_data [u] tmp ) 16384 )
        ? <= got 0 { ^ 0 } {}
        : b _ok ( vec_set_len [u] tmp got )
        ( __r_cat . c rxbuf tmp )
        ^ 1
    }
}

// Append b onto a in place.
@ __r_cat ( Vec u ) a ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    : ~ i k 0
    ~ < k n { ( vec_push [u] a ?? ( vec_get [u] b k ) { T x → x F _ → # u 0 } ) = k + k 1 }
}

// Read exactly one full reply from the socket. Reads more bytes whenever the
// buffered prefix is an incomplete RESP value, then drops the consumed bytes.
@ __r_read_reply * RedisConnImpl c → !RedisReply RedisErr {
    : ~ b spin T
    ~ spin {
        : RespParse p ( resp_parse . c rxbuf 0 )
        ? == . p status 0 {
            : i consumed . p consumed
            : i have ( vec_len [u] . c rxbuf )
            : ( Vec u ) rest ( bytes_slice . c rxbuf consumed have )
            ( vec_free [u] . c rxbuf )
            = . c rxbuf rest
            : RedisReply rep . p reply
            ( mem_take rep )  // the reply leaves the parse result
            ^ @ !RedisReply RedisErr { T rep }
        } {}
        ? == . p status 2 { ^ @ !RedisReply RedisErr { F # RedisErr RedisProtocol } } {}
        // incomplete: the partial arena goes with `p`; pull more bytes
        ? == ( __r_fill c ) 0 { ^ @ !RedisReply RedisErr { F # RedisErr RedisIo } } {}
    }
    ^ @ !RedisReply RedisErr { F # RedisErr RedisIo }
}

// ── command round-trip ─────────────────────────────────────────────

// Send a command (array of bulk strings) and return its reply. A RESP error
// reply is surfaced as RedisServerError with the text in conn.lasterr. The
// caller keeps `args` and owns the returned reply.
@ redis_command RedisConn c__h ( Vec String ) args → !RedisReply RedisErr { ^ ( __redis_command ( __RedisConn_ptr c__h ) args ) }

@ __redis_command * RedisConnImpl c ( Vec String ) args → !RedisReply RedisErr {
    : ( Vec u ) req ( resp_encode args )
    : i ok ( __r_write c req )
    ? == ok 0 { ^ @ !RedisReply RedisErr { F # RedisErr RedisIo } } {}
    : !RedisReply RedisErr rr ( __r_read_reply c )
    ?? rr {
        F e → ^ @ !RedisReply RedisErr { F e }
        T rep → {
            : i root ( resp_reply_root rep )
            ? == ( resp_node_kind rep root ) 3 {
                ( string_free . c lasterr )
                = . c lasterr ( string_from ( resp_node_str rep root ) )
                ^ @ !RedisReply RedisErr { F # RedisErr RedisServerError }
            } {}
            ^ @ !RedisReply RedisErr { T rep }
        }
    }
}

// ── argument builders ──────────────────────────────────────────────

@ redis_args → ( Vec String ) { ^ ( vec_new [String] ) }

@ redis_arg ( Vec String ) v s a → v { ( vec_push [String] v ( string_from a ) ) }

@ redis_arg_i ( Vec String ) v i n → v {
    : String s ( string_new ) ( string_push_int s n ) ( vec_push [String] v s )
}

// Let go of `v` now rather than at the end of its owner's scope.
@ redis_args_free sink ( Vec String ) v → v {}

@ __args1 s a → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] ) ( redis_arg v a ) ^ v
}

@ __args2 s a s b → ( Vec String ) {
    : ( Vec String ) v ( __args1 a ) ( redis_arg v b ) ^ v
}

@ __args3 s a s b s d → ( Vec String ) {
    : ( Vec String ) v ( __args2 a b ) ( redis_arg v d ) ^ v
}

// Build and send in one shot; the args go with the call.
@ __cmd_reply * RedisConnImpl c sink ( Vec String ) args → !RedisReply RedisErr {
    ^ ( __redis_command c args )
}

// ── typed reply extractors ─────────────────────────────────────────

// Integer reply (e.g. DEL, INCR, EXISTS count).
@ __reply_int * RedisConnImpl c ( Vec String ) args → !i RedisErr {
    ?? ( __cmd_reply c args ) {
        F e → ^ @ !i RedisErr { F e }
        T rep → {
            : i root ( resp_reply_root rep )
            : ~ i out 0
            ? == ( resp_node_kind rep root ) 1 { = out ( resp_node_int rep root ) } {}
            ^ @ !i RedisErr { T out }
        }
    }
}

// Integer reply interpreted as a boolean (1 → true).
@ __reply_bool * RedisConnImpl c ( Vec String ) args → !b RedisErr {
    ?? ( __reply_int c args ) {
        F e → ^ @ !b RedisErr { F e }
        T n → ^ @ !b RedisErr { T == n 1 }
    }
}

// Status reply (+OK and friends); we only care that it wasn't an error.
@ __reply_ok * RedisConnImpl c ( Vec String ) args → !v RedisErr {
    ?? ( __cmd_reply c args ) {
        F e → ^ @ !v RedisErr { F e }
        T rep → { ^ @ !v RedisErr { T 0 } }
    }
}

// Bulk-string reply, nil-aware. Integers are rendered to text so commands
// that may answer either way still produce a value.
@ __reply_str * RedisConnImpl c ( Vec String ) args → !RedisStr RedisErr {
    ?? ( __cmd_reply c args ) {
        F e → ^ @ !RedisStr RedisErr { F e }
        T rep → {
            : i root ( resp_reply_root rep )
            : i k ( resp_node_kind rep root )
            : ~ i found 0
            : ~ String val ( string_new )
            ? == k 2 {
                = found 1
                = val ( string_from ( resp_node_str rep root ) )
            } {
                ? == k 1 { = found 1 ( string_push_int val ( resp_node_int rep root ) ) } {}
            }
            ^ @ !RedisStr RedisErr { T @ RedisStr { found val } }
        }
    }
}

// Array reply flattened to a Vec of owned Strings (bulk elements; integer
// elements rendered; nils → empty string). Nil array → empty Vec.
@ __reply_strvec * RedisConnImpl c ( Vec String ) args → !( Vec String ) RedisErr {
    ?? ( __cmd_reply c args ) {
        F e → ^ @ !( Vec String ) RedisErr { F e }
        T rep → {
            : i root ( resp_reply_root rep )
            : ( Vec String ) out ( vec_new [String] )
            ? == ( resp_node_kind rep root ) 4 {
                : i n ( resp_node_arr_len rep root )
                : ~ i k 0
                ~ < k n {
                    : i el ( resp_node_arr_at rep root k )
                    : i ek ( resp_node_kind rep el )
                    ? == ek 1 {
                        : String s ( string_new ) ( string_push_int s ( resp_node_int rep el ) )
                        ( vec_push [String] out s )
                    } {
                        ( vec_push [String] out ( string_from ( resp_node_str rep el ) ) )
                    }
                    = k + k 1
                }
            } {}
            ^ @ !( Vec String ) RedisErr { T out }
        }
    }
}

// ── connection ─────────────────────────────────────────────────────

// tlsmode: 0 plaintext · 1 TLS no-verify · 2 TLS verify-full
@ __redis_open s host i port i tlsmode s server_name → !RedisConn RedisErr {
    : i rawfd ( nurl_tcp_connect host port )
    ? != ( nurl_tcp_err_kind rawfd ) 0 {
        ( nurl_tcp_close rawfd )  // failed handles still own their allocation
        ^ @ !RedisConn RedisErr { F # RedisErr RedisConnFail }
    } {}

    // The handle first: a failed TLS upgrade lets go of it, and its drop
    // closes the socket.
    : i c__box ( rcbox_zero [RedisConnImpl] )
    : RedisConn h @ RedisConn { # s c__box }
    : *RedisConnImpl c ( rcbox_ptr [RedisConnImpl] c__box )
    = . c tls 0
    = . c raw rawfd
    = . c tcp @ TcpConn { # s rawfd 0 0 }
    = . c tc # *TlsConn 0
    = . c rxbuf ( vec_new [u] )
    = . c lasterr ( string_new )
    = . c host_name ( string_from host )
    = . c port_num port
    = . c db_index 0

    ? > tlsmode 0 {
        : !*TlsConn TlsErr tr ? >= tlsmode 2 ( tls_attach_verify rawfd server_name ) ( tls_attach rawfd server_name )
        ?? tr {
            T tc → { = . c tls 1 = . c tc tc }
            F _ → { ^ @ !RedisConn RedisErr { F # RedisErr RedisTls } }
        }
    } {}
    ^ @ !RedisConn RedisErr { T h }
}

@ redis_connect s host i port → !RedisConn RedisErr {
    ^ ( __redis_open host port 0 `` )
}

// verify != 0 → verify-full (chain + hostname); verify == 0 → encrypt only.
@ redis_connect_tls s host i port s server_name i verify → !RedisConn RedisErr {
    ^ ( __redis_open host port ? != verify 0 2 1 server_name )
}

// Let go of `c` now rather than at the end of its owner's scope (the last
// owner closes the connection).
@ redis_close sink RedisConn c → v {}

@ redis_last_error RedisConn c__h → s {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( string_data . c lasterr )
}

@ redis_is_tls RedisConn c__h → b {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ == . c tls 1
}

// ── connection commands ────────────────────────────────────────────

// AUTH: one-arg (password only) or two-arg (ACL user + password). Pass an
// empty user for the legacy single-argument form.
@ redis_auth RedisConn c__h s user s password → !v RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ? == ( nurl_str_len user ) 0 { ^ ( __reply_ok c ( __args2 `AUTH` password ) ) } {}
    ^ ( __reply_ok c ( __args3 `AUTH` user password ) )
}

@ redis_select RedisConn c__h i db → !v RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    : ( Vec String ) a ( __args1 `SELECT` ) ( redis_arg_i a db )
    : !v RedisErr r ( __reply_ok c a )
    ?? r { T _ → { = . c db_index db ^ @ !v RedisErr { T 0 } } F e → ^ @ !v RedisErr { F e } }
}

@ redis_ping RedisConn c__h → !b RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ?? ( __cmd_reply c ( __args1 `PING` ) ) {
        F e → ^ @ !b RedisErr { F e }
        T rep → {
            : i root ( resp_reply_root rep )
            : b ok & == ( resp_node_kind rep root ) 2 != ( nurl_str_eq ( resp_node_str rep root ) `PONG` ) 0
            ^ @ !b RedisErr { T ok }
        }
    }
}

@ redis_echo RedisConn c__h s msg → !RedisStr RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_str c ( __args2 `ECHO` msg ) )
}

// ── strings / keys ─────────────────────────────────────────────────

@ redis_set RedisConn c__h s key s val → !v RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_ok c ( __args3 `SET` key val ) )
}

@ redis_get RedisConn c__h s key → !RedisStr RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_str c ( __args2 `GET` key ) )
}

@ redis_del RedisConn c__h s key → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args2 `DEL` key ) )
}

@ redis_exists RedisConn c__h s key → !b RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_bool c ( __args2 `EXISTS` key ) )
}

@ redis_incr RedisConn c__h s key → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args2 `INCR` key ) )
}

@ redis_decr RedisConn c__h s key → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args2 `DECR` key ) )
}

@ redis_incrby RedisConn c__h s key i n → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    : ( Vec String ) a ( __args2 `INCRBY` key ) ( redis_arg_i a n )
    ^ ( __reply_int c a )
}

@ redis_expire RedisConn c__h s key i secs → !b RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    : ( Vec String ) a ( __args2 `EXPIRE` key ) ( redis_arg_i a secs )
    ^ ( __reply_bool c a )
}

@ redis_ttl RedisConn c__h s key → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args2 `TTL` key ) )
}

@ redis_keys RedisConn c__h s pattern → !( Vec String ) RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_strvec c ( __args2 `KEYS` pattern ) )
}

// ── lists ──────────────────────────────────────────────────────────

@ redis_lpush RedisConn c__h s key s val → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args3 `LPUSH` key val ) )
}

@ redis_rpush RedisConn c__h s key s val → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args3 `RPUSH` key val ) )
}

@ redis_llen RedisConn c__h s key → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args2 `LLEN` key ) )
}

@ redis_lrange RedisConn c__h s key i start i stop → !( Vec String ) RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    : ( Vec String ) a ( __args2 `LRANGE` key ) ( redis_arg_i a start ) ( redis_arg_i a stop )
    ^ ( __reply_strvec c a )
}

// ── hashes ─────────────────────────────────────────────────────────

@ redis_hset RedisConn c__h s key s field s val → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    : ( Vec String ) a ( __args3 `HSET` key field ) ( redis_arg a val )
    ^ ( __reply_int c a )
}

@ redis_hget RedisConn c__h s key s field → !RedisStr RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_str c ( __args3 `HGET` key field ) )
}

// Flat [field, value, field, value, …] of the whole hash.
@ redis_hgetall RedisConn c__h s key → !( Vec String ) RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_strvec c ( __args2 `HGETALL` key ) )
}

// ── sets ───────────────────────────────────────────────────────────

@ redis_sadd RedisConn c__h s key s member → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args3 `SADD` key member ) )
}

@ redis_smembers RedisConn c__h s key → !( Vec String ) RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_strvec c ( __args2 `SMEMBERS` key ) )
}

// ── pub/sub ────────────────────────────────────────────────────────

@ redis_publish RedisConn c__h s channel s msg → !i RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_int c ( __args3 `PUBLISH` channel msg ) )
}

// Decode one pub/sub reply array into a RedisMessage (owning copies of the
// channel / pattern / payload text).
@ __decode_message RedisReply rep → RedisMessage {
    : i root ( resp_reply_root rep )
    : ~ i kind -1
    : ~ String channel ( string_new )
    : ~ String pattern ( string_new )
    : ~ String payload ( string_new )
    : ~ i count 0
    ? & == ( resp_node_kind rep root ) 4 >= ( resp_node_arr_len rep root ) 1 {
        : i n ( resp_node_arr_len rep root )
        : s verb ( resp_node_str rep ( resp_node_arr_at rep root 0 ) )
        ? != ( nurl_str_eq verb `message` ) 0 {
            = kind 0
            ? >= n 3 {
                = channel ( string_from ( resp_node_str rep ( resp_node_arr_at rep root 1 ) ) )
                = payload ( string_from ( resp_node_str rep ( resp_node_arr_at rep root 2 ) ) )
            } {}
        } {
            ? != ( nurl_str_eq verb `pmessage` ) 0 {
                = kind 3
                ? >= n 4 {
                    = pattern ( string_from ( resp_node_str rep ( resp_node_arr_at rep root 1 ) ) )
                    = channel ( string_from ( resp_node_str rep ( resp_node_arr_at rep root 2 ) ) )
                    = payload ( string_from ( resp_node_str rep ( resp_node_arr_at rep root 3 ) ) )
                } {}
            } {
                // (p)subscribe / (p)unsubscribe confirmation: [verb, name, count]
                ? != ( nurl_str_eq verb `subscribe` ) 0 { = kind 1 } {
                    ? != ( nurl_str_eq verb `unsubscribe` ) 0 { = kind 2 } {
                        ? != ( nurl_str_eq verb `psubscribe` ) 0 { = kind 4 } {
                            ? != ( nurl_str_eq verb `punsubscribe` ) 0 { = kind 5 } {} } } }
                ? >= n 3 {
                    : i is_pat | == kind 4 == kind 5
                    : String name ( string_from ( resp_node_str rep ( resp_node_arr_at rep root 1 ) ) )
                    ? is_pat { = pattern name } { = channel name }
                    = count ( resp_node_int rep ( resp_node_arr_at rep root 2 ) )
                } {}
            } }
    } {}
    ^ @ RedisMessage { kind channel pattern payload count }
}

@ __sub_cmd * RedisConnImpl c s verb s arg → !RedisMessage RedisErr {
    ?? ( __cmd_reply c ( __args2 verb arg ) ) {
        F e → ^ @ !RedisMessage RedisErr { F e }
        T rep → {
            : RedisMessage m ( __decode_message rep )
            ^ @ !RedisMessage RedisErr { T m }
        }
    }
}

// Subscribe to a channel (or pattern). Returns the subscription confirmation;
// thereafter call redis_next_message to receive published messages. While
// subscribed only (P)SUBSCRIBE / (P)UNSUBSCRIBE / PING are valid commands.
@ redis_subscribe RedisConn c__h s channel → !RedisMessage RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __sub_cmd c `SUBSCRIBE` channel )
}

@ redis_unsubscribe RedisConn c__h s channel → !RedisMessage RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __sub_cmd c `UNSUBSCRIBE` channel )
}

@ redis_psubscribe RedisConn c__h s pattern → !RedisMessage RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __sub_cmd c `PSUBSCRIBE` pattern )
}

@ redis_punsubscribe RedisConn c__h s pattern → !RedisMessage RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __sub_cmd c `PUNSUBSCRIBE` pattern )
}

// Block until the next pub/sub frame arrives, then decode it. Returns a
// `message` / `pmessage` for delivered payloads, or a (un)subscribe control
// frame; RedisIo on a closed connection.
@ redis_next_message RedisConn c__h → !RedisMessage RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ?? ( __r_read_reply c ) {
        F e → ^ @ !RedisMessage RedisErr { F e }
        T rep → {
            : RedisMessage m ( __decode_message rep )
            ^ @ !RedisMessage RedisErr { T m }
        }
    }
}

// ── admin ──────────────────────────────────────────────────────────

@ redis_flushdb RedisConn c__h → !v RedisErr {
    : *RedisConnImpl c ( __RedisConn_ptr c__h )
    ^ ( __reply_ok c ( __args1 `FLUSHDB` ) )
}
