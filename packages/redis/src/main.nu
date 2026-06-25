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
@ __run_cmd *RedisConn c ( Vec String ) args → v {
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
@ __subscribe_loop *RedisConn c ( Vec String ) toks i is_pattern → v {
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
@ __dispatch *RedisConn c ( Vec String ) toks → v {
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
    i tlsmode    // 0 plain, 1 tls insecure, 2 tls verify-full
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
        : String ui ( string_substr ( string_from url ) p - at p )
        : ?i colon ( string_index_of ui `:` )
        ?? colon {
            T ci2 → {
                = . c user ( string_substr ui 0 ci2 )
                = . c password ( string_substr ui + ci2 1 - ( string_len ui ) + ci2 1 )
            }
            F _ → { = . c password ui }
        }
        = hoststart + at 1
    } {}
    : i hostend ? != slash -1 slash n
    : String hostport ( string_substr ( string_from url ) hoststart - hostend hoststart )
    : ?i pc ( string_index_of hostport `:` )
    ?? pc {
        T pci → {
            = . c host ( string_substr hostport 0 pci )
            = . c port ( __atoi ( string_data ( string_substr hostport + pci 1 - ( string_len hostport ) + pci 1 ) ) )
        }
        F _ → { = . c host hostport }
    }
    ? != slash -1 {
        = . c db ( __atoi ( string_data ( string_substr ( string_from url ) + slash 1 - n + slash 1 ) ) )
    } {}
    ^ c
}

@ __connect ConnInfo ci → !*RedisConn RedisErr {
    ? > . ci tlsmode 0 {
        ^ ( redis_connect_tls ( string_data . ci host ) . ci port ( string_data . ci host ) ? >= . ci tlsmode 2 1 0 )
    } {}
    ^ ( redis_connect ( string_data . ci host ) . ci port )
}

@ __usage → v {
    ( nurl_print `redis (NURL) — a pure-NURL Redis client (RESP2, optional pure TLS)\n\n` )
    ( nurl_print `Usage:\n` )
    ( nurl_print `  redis [flags] ["redis://[user:pass@]host:port/db"]\n\n` )
    ( nurl_print `Flags:\n` )
    ( nurl_print `  -h HOST        host        (default $REDIS_HOST or 127.0.0.1)\n` )
    ( nurl_print `  -p PORT        port        (default $REDIS_PORT or 6379)\n` )
    ( nurl_print `  -a PASSWORD    AUTH password (default $REDIS_PASSWORD)\n` )
    ( nurl_print `  --user USER    ACL username for AUTH (Redis 6+)\n` )
    ( nurl_print `  -n DB          SELECT database index (default 0)\n` )
    ( nurl_print `  --tls          connect over TLS (verify-full)\n` )
    ( nurl_print `  --insecure     skip certificate verification\n` )
    ( nurl_print `  -c "CMD ARGS"  run one command and exit (otherwise start a REPL)\n` )
    ( nurl_print `  --help, -?     show this help and exit\n\n` )
    ( nurl_print `Examples:\n` )
    ( nurl_print `  redis -c "PING"\n` )
    ( nurl_print `  redis -h cache.example.com -p 6380 --tls -c "GET session:42"\n` )
    ( nurl_print `  redis "rediss://default:secret@cache.example.com:6380/0"\n` )
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    : i argc ( vec_len [String] args )

    : ~ ConnInfo ci @ ConnInfo {
        ( env_var_or `REDIS_HOST` `127.0.0.1` )
        ( __atoi ( string_data ( env_var_or `REDIS_PORT` `6379` ) ) )
        ( string_new )
        ( env_var_or `REDIS_PASSWORD` `` )
        0
        0
    }
    : ~ String oneshot ( string_new )
    : ~ b have_c F
    : ~ b want_help F
    : ~ i insecure 0

    : ~ i ai 1
    ~ < ai argc {
        : String a ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_new ) }
        : s as ( string_data a )
        ? ( nurl_str_eq as `-h` ) { = ai + ai 1 = . ci host ?? ( vec_get [String] args ai ) { T x → x F _ → . ci host } } {
        ? ( nurl_str_eq as `-p` ) { = ai + ai 1 = . ci port ( __atoi ( string_data ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_from `6379` ) } ) ) } {
        ? ( nurl_str_eq as `-a` ) { = ai + ai 1 = . ci password ?? ( vec_get [String] args ai ) { T x → x F _ → . ci password } } {
        ? ( nurl_str_eq as `--user` ) { = ai + ai 1 = . ci user ?? ( vec_get [String] args ai ) { T x → x F _ → . ci user } } {
        ? ( nurl_str_eq as `-n` ) { = ai + ai 1 = . ci db ( __atoi ( string_data ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_from `0` ) } ) ) } {
        ? ( nurl_str_eq as `--tls` ) { ? == . ci tlsmode 0 { = . ci tlsmode 2 } {} } {
        ? ( nurl_str_eq as `--insecure` ) { = insecure 1 } {
        ? ( nurl_str_eq as `-c` ) { = ai + ai 1 = oneshot ?? ( vec_get [String] args ai ) { T x → x F _ → ( string_new ) } = have_c T } {
        ? | ( nurl_str_starts as `redis://` ) ( nurl_str_starts as `rediss://` ) { = ci ( __parse_url as ci ) } {
        ? | ( nurl_str_eq as `--help` ) ( nurl_str_eq as `-?` ) { = want_help T } {
            ( nurl_eprint `redis: unknown argument: ` ) ( nurl_eprint as ) ( nurl_eprint `\n` )
        } } } } } } } } } }
        = ai + ai 1
    }

    ? want_help { ( __usage ) ^ 0 } {}

    // --insecure downgrades verify-full to encrypt-only.
    ? & == insecure 1 > . ci tlsmode 0 { = . ci tlsmode 1 } {}

    : i tty # i ( isatty # i32 0 )

    : !*RedisConn RedisErr cr ( __connect ci )
    ?? cr {
        F e → {
            ( nurl_eprint `redis: connection failed: ` ) ( nurl_eprint ( redis_err_name e ) ) ( nurl_eprint `\n` )
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
            ^ 0
        }
    }
}
