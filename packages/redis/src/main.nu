// packages/redis/src/main.nu — the `redis` command: a small redis-cli-style
// client built on the pure-NURL Redis client. Connects over RESP2 with an
// optional pure-NURL TLS upgrade (rediss://, no OpenSSL on the target),
// authenticates with AUTH, runs one command with -c or starts a REPL.
//
//   redis [flags] ["redis://[user:pass@]host:port/db"]
//     -h HOST        host (default $REDIS_HOST or 127.0.0.1)
//     -p PORT        port (default $REDIS_PORT or 6379)
//     -a PASSWORD    AUTH password (default $REDIS_PASSWORD)
//     --user USER    ACL username for AUTH (Redis 6+)
//     -n DB          SELECT database index (default 0)
//     --tls          connect over TLS (verify-full)
//     --insecure     with --tls / rediss://, skip certificate verification
//     -c "CMD ARGS"  run one command and exit; otherwise start a REPL
//   A rediss:// URL implies --tls.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `deps/cli/src/cli.nu`
$ `redis.nu`

& `c` @ isatty i32 fd → i32

@ __atoi s str → i {
    : i n ( nurl_str_len str )
    : ~ i v 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get str k )
        ? & >= c 48 <= c 57 { = v + * v 10 - c 48 } {}
        = k + k 1
    }
    ^ v
}

@ __print_int i n → v {
    : String s ( string_new ) ( string_push_int s n )
    ( nurl_print ( string_data s ) ) ( string_free s )
}

// ── reply rendering (redis-cli style) ──────────────────────────────

@ __print_node RedisReply r i node i depth → v {
    : i k ( resp_node_kind r node )
    ? == k 0 { ( nurl_print `(nil)\n` ) ^ v } {}
    ? == k 1 { ( nurl_print `(integer) ` ) ( __print_int ( resp_node_int r node ) ) ( nurl_print `\n` ) ^ v } {}
    ? == k 3 { ( nurl_print `(error) ` ) ( nurl_print ( resp_node_str r node ) ) ( nurl_print `\n` ) ^ v } {}
    ? == k 2 {
        ( nurl_print `"` ) ( nurl_print ( resp_node_str r node ) ) ( nurl_print `"\n` )
        ^ v
    } {}
    // array
    : i n ( resp_node_arr_len r node )
    ? == n 0 { ( nurl_print `(empty array)\n` ) ^ v } {}
    : ~ i j 0
    ~ < j n {
        : i el ( resp_node_arr_at r node j )
        ( __print_int + j 1 ) ( nurl_print `) ` )
        ? == ( resp_node_kind r el ) 4 {
            ( nurl_print `\n` ) ( __print_node r el + depth 1 )
        } {
            ( __print_node r el depth )
        }
        = j + j 1
    }
}

// Send one already-built command, print its reply, and free args.
@ __run_cmd * RedisConn c ( Vec String ) args → v {
    ?? ( redis_command c args ) {
        T rep → { ( __print_node rep ( resp_reply_root rep ) 0 ) ( resp_reply_free rep ) }
        F e → {
            : b srv ?? e { RedisServerError → T _ → F }
            ? srv {
                ( nurl_eprint `(error) ` ) ( nurl_eprint ( redis_last_error c ) ) ( nurl_eprint `\n` )
            } {
                ( nurl_eprint `(error) ` ) ( nurl_eprint ( redis_err_name e ) ) ( nurl_eprint `\n` )
            }
        }
    }
    ( redis_args_free args )
}

// Case-insensitive ASCII equality (for command-name dispatch).
@ __rci_eq s a s b → b {
    : i la ( nurl_str_len a )
    ? != la ( nurl_str_len b ) { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ < k la {
        : ~ i ca ( nurl_str_get a k )
        : ~ i cb ( nurl_str_get b k )
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { = ok F } {}
        = k + k 1
    }
    ^ ok
}

@ __print_msg RedisMessage m → v {
    : i k ( redis_message_kind m )
    ? == k 0 {
        ( nurl_print `message ` ) ( nurl_print ( redis_message_channel m ) )
        ( nurl_print ` "` ) ( nurl_print ( redis_message_payload m ) ) ( nurl_print `"\n` )
    } {
        ? == k 3 {
            ( nurl_print `pmessage ` ) ( nurl_print ( redis_message_pattern m ) )
            ( nurl_print ` ` ) ( nurl_print ( redis_message_channel m ) )
            ( nurl_print ` "` ) ( nurl_print ( redis_message_payload m ) ) ( nurl_print `"\n` )
        } {
            : i sub | == k 1 == k 4
            ( nurl_print ? sub `(subscribed ` `(unsubscribed ` )
            ( nurl_print ? | == k 4 == k 5 ( redis_message_pattern m ) ( redis_message_channel m ) )
            ( nurl_print `, ` ) ( __print_int ( redis_message_count m ) ) ( nurl_print ` active)\n` )
        } }
}

// SUBSCRIBE / PSUBSCRIBE one or more channels, then print delivered messages
// until the connection closes (Ctrl-C / EOF). `toks` is the whole command
// (toks[0] = the verb, toks[1..] = channels / patterns).
@ __subscribe_loop * RedisConn c ( Vec String ) toks i is_pattern → v {
    : i n ( vec_len [String] toks )
    : ~ i k 1
    ~ < k n {
        : s ch ( string_data ?? ( vec_get [String] toks k ) { T x → x F _ → ( string_new ) } )
        : !RedisMessage RedisErr sr ? != is_pattern 0 ( redis_psubscribe c ch ) ( redis_subscribe c ch )
        ?? sr {
            T m → { ( __print_msg m ) ( redis_message_free m ) }
            F _ → { ( nurl_eprint `(error) subscribe failed\n` ) ^ v }
        }
        = k + k 1
    }
    : ~ b go T
    ~ go {
        ?? ( redis_next_message c ) {
            T m → { ( __print_msg m ) ( redis_message_free m ) }
            F _ → { = go F }
        }
    }
}

// Route a parsed command: SUBSCRIBE / PSUBSCRIBE enter the message loop,
// everything else is a one-shot request/reply. Frees `toks` either way.
@ __dispatch * RedisConn c ( Vec String ) toks → v {
    : s cmd0 ( string_data ?? ( vec_get [String] toks 0 ) { T x → x F _ → ( string_new ) } )
    ? ( __rci_eq cmd0 `subscribe` ) { ( __subscribe_loop c toks 0 ) ( redis_args_free toks ) ^ v } {}
    ? ( __rci_eq cmd0 `psubscribe` ) { ( __subscribe_loop c toks 1 ) ( redis_args_free toks ) ^ v } {}
    ( __run_cmd c toks )
}

// ── command-line tokenizer (whitespace split, "double quotes") ─────

@ __tokenize s line → ( Vec String ) {
    : i n ( nurl_str_len line )
    : ( Vec String ) out ( vec_new [String] )
    : ~ String cur ( string_new )
    : ~ i incur 0
    : ~ i inq 0
    : ~ i k 0
    ~ < k n {
        : i ch ( nurl_str_get line k )
        ? == inq 1 {
            ? == ch 34 { = inq 0 } { ( string_push_char cur ch ) = incur 1 }
        } {
            ? == ch 34 { = inq 1 = incur 1 } {
                ? | == ch 32 | == ch 9 == ch 13 {
                    ? == incur 1 { ( vec_push [String] out cur ) = cur ( string_new ) = incur 0 } {}
                } {
                    ( string_push_char cur ch ) = incur 1
                }
            }
        }
        = k + k 1
    }
    ? == incur 1 { ( vec_push [String] out cur ) } { ( string_free cur ) }
    ^ out
}

// ── connection info ────────────────────────────────────────────────

: ConnInfo {
    String host
    i port
    String user
    String password
    i db
    i tlsmode  // 0 plain, 1 tls insecure, 2 tls verify-full
}

// redis://[user:pass@]host[:port][/db]  (rediss:// → TLS)
@ __parse_url s url ConnInfo ci → ConnInfo {
    : ~ ConnInfo c ci
    : i n ( nurl_str_len url )
    : ~ i p 0
    ? ( nurl_str_starts url `rediss://` ) { = p 9 ? == . c tlsmode 0 { = . c tlsmode 2 } {} } {}
    ? ( nurl_str_starts url `redis://` ) { = p 8 } {}
    : ~ i at -1
    : ~ i slash -1
    : ~ i k p
    ~ < k n {
        : i ch ( nurl_str_get url k )
        ? & == ch 64 == at -1 { = at k } {}
        ? & == ch 47 == slash -1 { = slash k } {}
        = k + k 1
    }
    : ~ i hoststart p
    ? & != at -1 | == slash -1 < at slash {
        : String usrc ( string_from url )
        : String ui ( string_substr usrc p - at p )
        ( string_free usrc )
        : ?i colon ( string_index_of ui `:` )
        ?? colon {
            T ci2 → {
                ( string_free . c user ) = . c user ( string_substr ui 0 ci2 )
                ( string_free . c password ) = . c password ( string_substr ui + ci2 1 - ( string_len ui ) + ci2 1 )
                ( string_free ui )
            }
            F _ → { ( string_free . c password ) = . c password ui }
        }
        = hoststart + at 1
    } {}
    : i hostend ? != slash -1 slash n
    : String uall ( string_from url )
    : String hostport ( string_substr uall hoststart - hostend hoststart )
    : ?i pc ( string_index_of hostport `:` )
    ?? pc {
        T pci → {
            ( string_free . c host ) = . c host ( string_substr hostport 0 pci )
            : String pstr ( string_substr hostport + pci 1 - ( string_len hostport ) + pci 1 )
            = . c port ( __atoi ( string_data pstr ) )
            ( string_free pstr )
            ( string_free hostport )
        }
        F _ → { ( string_free . c host ) = . c host hostport }
    }
    ? != slash -1 {
        : String dstr ( string_substr uall + slash 1 - n + slash 1 )
        = . c db ( __atoi ( string_data dstr ) )
        ( string_free dstr )
    } {}
    ( string_free uall )
    ^ c
}

@ __connect ConnInfo ci → !*RedisConn RedisErr {
    ? > . ci tlsmode 0 {
        ^ ( redis_connect_tls ( string_data . ci host ) . ci port ( string_data . ci host ) ? >= . ci tlsmode 2 1 0 )
    } {}
    ^ ( redis_connect ( string_data . ci host ) . ci port )
}

// The whole program is one default command (redis-cli style): flags,
// an optional redis://…/rediss://… URL positional, then one-shot or REPL.
@ __redis_go CliCtx x → i {
    : String hostv ( ctx_str x `host` )
    : String passv ( ctx_str x `password` )
    : String userv ( ctx_str x `user` )
    : ~ ConnInfo ci @ ConnInfo {
        hostv
        ( ctx_int x `port` )
        userv
        passv
        ( ctx_int x `db` )
        ? ( ctx_bool x `tls` ) { 2 } { 0 }
    }
    : String oneshot ( ctx_str x `command` )
    : b have_c > ( string_len oneshot ) 0
    : i insecure ? ( ctx_bool x `insecure` ) { 1 } { 0 }
    // an optional redis:// / rediss:// URL positional overrides the flags
    ? > ( ctx_nargs x ) 0 {
        : String u ( ctx_arg x 0 )
        : s us ( string_data u )
        ? | ( nurl_str_starts us `redis://` ) ( nurl_str_starts us `rediss://` ) {
            = ci ( __parse_url us ci )
        } {
            ( nurl_eprint `redis: unknown argument: ` ) ( nurl_eprint us ) ( nurl_eprint `\n` )
        }
    } {}

    // --insecure downgrades verify-full to encrypt-only.
    ? & == insecure 1 > . ci tlsmode 0 { = . ci tlsmode 1 } {}

    : i tty # i ( isatty # i32 0 )

    : !*RedisConn RedisErr cr ( __connect ci )
    ?? cr {
        F e → {
            ( nurl_eprint `redis: connection failed: ` ) ( nurl_eprint ( redis_err_name e ) ) ( nurl_eprint `\n` )
            ( string_free . ci host ) ( string_free . ci user ) ( string_free . ci password )
            ( string_free oneshot )
            ^ 1
        }
        T c → {
            // AUTH if a password was supplied.
            ? > ( string_len . ci password ) 0 {
                ?? ( redis_auth c ( string_data . ci user ) ( string_data . ci password ) ) {
                    T _ → {}
                    F _ → {
                        ( nurl_eprint `redis: AUTH failed: ` ) ( nurl_eprint ( redis_last_error c ) ) ( nurl_eprint `\n` )
                        ( redis_close c ) ^ 1
                    }
                }
            } {}
            // SELECT a non-default database.
            ? > . ci db 0 {
                ?? ( redis_select c . ci db ) { T _ → {} F _ → {} }
            } {}

            ? have_c {
                : ( Vec String ) toks ( __tokenize ( string_data oneshot ) )
                ? > ( vec_len [String] toks ) 0 { ( __dispatch c toks ) } { ( redis_args_free toks ) }
            } {
                ? != tty 0 {
                    ( nurl_print `redis (NURL) — pure-NURL client. Type a command, or 'quit' to exit.\n` )
                } {}
                : ~ b running T
                ~ running {
                    ? != tty 0 {
                        ( nurl_print ( string_data . ci host ) ) ( nurl_print `:` ) ( __print_int . ci port ) ( nurl_print `> ` )
                    } {}
                    : String line ( read_line )
                    ? & == ( string_len line ) 0 ( stdin_eof ) {
                        = running F
                        ? != tty 0 { ( nurl_print `\n` ) } {}
                    } {
                        : ( Vec String ) toks ( __tokenize ( string_data line ) )
                        : i tn ( vec_len [String] toks )
                        ? == tn 0 { ( redis_args_free toks ) } {
                            : s cmd0 ( string_data ?? ( vec_get [String] toks 0 ) { T x → x F _ → ( string_new ) } )
                            ? | ( nurl_str_eq cmd0 `quit` ) ( nurl_str_eq cmd0 `exit` ) {
                                ( redis_args_free toks ) = running F
                            } {
                                ( __dispatch c toks )
                            }
                        }
                    }
                    ( string_free line )
                }
            }
            ( redis_close c )
            ( string_free . ci host ) ( string_free . ci user ) ( string_free . ci password )
            ( string_free oneshot )
            ^ 0
        }
    }
}

@ main → i {
    : *Cli c ( cli_new `redis` `a pure-NURL Redis client (RESP2, optional pure TLS); redis://[user:pass@]host:port/db as the argument` `0.2.0` )
    ( cli_flag_str c `host` 104 `HOST` `server host` `127.0.0.1` `REDIS_HOST` )
    ( cli_flag_int c `port` 112 `PORT` `server port` 6379 `REDIS_PORT` )
    ( cli_flag_str c `password` 97 `PASSWORD` `AUTH password` `` `REDIS_PASSWORD` )
    ( cli_flag_str c `user` 0 `USER` `ACL username for AUTH (Redis 6+)` `` `` )
    ( cli_flag_int c `db` 110 `DB` `SELECT database index` 0 `` )
    ( cli_flag_bool c `tls` 0 `connect over TLS (verify-full)` )
    ( cli_flag_bool c `insecure` 0 `skip certificate verification (encrypt-only)` )
    ( cli_flag_str c `command` 99 `CMD` `run one command and exit (otherwise start a REPL)` `` `` )
    ( cli_default c \ CliCtx x → i { ^ ( __redis_go x ) } )
    : i rc ( cli_run c )
    ( cli_free c )
    ^ rc
}
