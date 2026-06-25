# redis — a pure-NURL Redis client

A small, dependency-light Redis client written entirely in NURL. It speaks
the RESP2 wire protocol over a plain libc TCP socket, and can upgrade to TLS
(`rediss://`) using the pure-NURL TLS client — **no `hiredis`, no OpenSSL,
nothing installed on the target.** The binaries link `libc` only.

It ships as two things:

- **a reusable library** (`src/redis.nu` + `src/resp.nu`) you import into your
  own program, and
- **a `redis` command** — a small redis-cli-style REPL / one-shot client,
  handy for testing and scripting.

## Install

```sh
nurlpkg install redis
```

This puts a `redis` binary on your `PATH`. Or build from a checkout:

```sh
cd packages/redis
nurlpkg install                 # resolve deps/ (the tls package)
../../nurl.sh src/main.nu redis
```

## The `redis` command

```
redis [flags] ["redis://[user:pass@]host:port/db"]
  -h HOST        host          (default $REDIS_HOST or 127.0.0.1)
  -p PORT        port          (default $REDIS_PORT or 6379)
  -a PASSWORD    AUTH password (default $REDIS_PASSWORD)
  --user USER    ACL username for AUTH (Redis 6+)
  -n DB          SELECT database index (default 0)
  --tls          connect over TLS (verify-full)
  --insecure     with --tls / rediss://, skip certificate verification
  -c "CMD ARGS"  run one command and exit; otherwise start a REPL
```

```sh
redis -c "PING"                                   # "PONG"
redis -c "SET greeting hello" && redis -c "GET greeting"
redis -h cache.example.com -p 6380 --tls -c "GET session:42"
redis "rediss://default:secret@cache.example.com:6380/0"
```

In the REPL, type commands directly; `quit` (or EOF) exits. Double-quoted
arguments may contain spaces: `SET phrase "hello world"`.

## The library

```nurl
$ `deps/redis/src/redis.nu`

@ main → i {
    : *RedisConn c ?? ( redis_connect `127.0.0.1` 6379 ) {
        T x → x
        F e → { ( nurl_eprint ( redis_err_name e ) ) ^ 1 }
    }

    ?? ( redis_set c `user:1:name` `Ada` ) { T _ → {} F _ → {} }

    ?? ( redis_get c `user:1:name` ) {
        T rs → {
            ? ( redis_str_is_nil rs ) { ( nurl_print `(missing)\n` ) }
                                      { ( nurl_print ( redis_str_val rs ) ) ( nurl_print `\n` ) }
            ( redis_str_free rs )
        }
        F _ → {}
    }

    ( redis_close c )
    ^ 0
}
```

### Connecting

| Function | Returns |
| --- | --- |
| `redis_connect host port` | `!*RedisConn RedisErr` |
| `redis_connect_tls host port server_name verify` | `!*RedisConn RedisErr` — `verify != 0` ⇒ verify-full |
| `redis_auth conn user password` | `!v RedisErr` — empty `user` ⇒ legacy single-arg AUTH |
| `redis_select conn db` | `!v RedisErr` |
| `redis_close conn` | `v` |

### Typed commands

Strings / keys: `redis_set` `redis_get` `redis_del` `redis_exists`
`redis_incr` `redis_decr` `redis_incrby` `redis_expire` `redis_ttl`
`redis_keys`.
Lists: `redis_lpush` `redis_rpush` `redis_llen` `redis_lrange`.
Hashes: `redis_hset` `redis_hget` `redis_hgetall`.
Sets: `redis_sadd` `redis_smembers`.
Misc: `redis_ping` `redis_echo` `redis_flushdb`.

### Pub/sub

Publish with `redis_publish conn channel msg` (returns the number of
subscribers reached). To receive, `redis_subscribe` / `redis_psubscribe` a
channel or pattern, then loop on `redis_next_message`, which blocks until the
next frame arrives:

```nurl
?? ( redis_subscribe c `news` ) { T m → ( redis_message_free m ) F _ → {} }
: ~ b go T
~ go {
    ?? ( redis_next_message c ) {
        T m → {
            ? ( redis_message_is_payload m )
              { ( nurl_print ( redis_message_channel m ) ) ( nurl_print `: ` )
                ( nurl_print ( redis_message_payload m ) ) ( nurl_print `\n` ) } {}
            ( redis_message_free m )
        }
        F _ → { = go F }
    }
}
```

A `RedisMessage` carries `redis_message_kind` (0 message · 1 subscribe ·
2 unsubscribe · 3 pmessage · 4 psubscribe · 5 punsubscribe),
`redis_message_channel`, `redis_message_pattern` (p* variants),
`redis_message_payload`, `redis_message_count` (live subscription count on
confirmations), and `redis_message_is_payload`. Release it with
`redis_message_free`. `redis_unsubscribe` / `redis_punsubscribe` leave
subscriber mode. From the CLI, `redis -c "SUBSCRIBE chan1 chan2"` (or
`PSUBSCRIBE pat.*`) subscribes and streams messages until interrupted.

`redis_get` / `redis_hget` / `redis_echo` return a `RedisStr` (a nil-aware
optional string): check `redis_str_is_nil`, read `redis_str_val`, release
with `redis_str_free`. The `*_strvec` commands return an owned `Vec String`.

### Arbitrary commands

Anything not covered by a helper goes through `redis_command`, which returns
the raw reply tree:

```nurl
: ( Vec String ) a ( redis_args )
( redis_arg a `SET` ) ( redis_arg a `k` ) ( redis_arg a `v` )
( redis_arg a `EX` ) ( redis_arg_i a 60 )
?? ( redis_command c a ) {
    T rep → { /* walk with resp_node_* */ ( resp_reply_free rep ) }
    F e   → { /* RedisServerError text is ( redis_last_error c ) */ }
}
( redis_args_free a )
```

The reply tree (`src/resp.nu`) is a flat node arena, so it handles arbitrary
nesting (pub/sub, `XRANGE`, `COMMAND`, …):
`resp_reply_root`, `resp_node_kind` (0 nil · 1 int · 2 string · 3 error ·
4 array), `resp_node_int`, `resp_node_str`, `resp_node_is_nil`,
`resp_node_arr_len`, `resp_node_arr_at`.

## Tests

`tests/resp_test.nu` unit-tests the RESP codec with no server needed.
`tests/live_test.nu` exercises the typed API against a live server and runs
clean under AddressSanitizer. `tests/live_smoke.sh` wires both up against a
local Redis (or a throwaway Docker one). See each file's header for the exact
build commands.

## License

MIT OR Apache-2.0.
