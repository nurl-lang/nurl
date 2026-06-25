// packages/redis/tests/live_test.nu — exercises the typed client API against
// a live server. Needs Redis on 127.0.0.1:16379 (see tests/live_smoke.sh).
// Frees every reply so it runs clean under AddressSanitizer.
//
//   cd packages/redis
//   NURL_SAN=1 NURL_STDLIB=<repo-root> ../../nurl.sh tests/live_test.nu /tmp/rlt
//   /tmp/rlt

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/redis.nu`

: ~ i g_fail 0

@ __ok s name b cond → v {
    ? cond { ( nurl_print `ok   ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

@ __free_strvec ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [String] v k ) { T s → ( string_free s ) F _ → {} } = k + k 1 }
    ( vec_free [String] v )
}

@ main → i {
    : !*RedisConn RedisErr cr ( redis_connect `127.0.0.1` 16379 )
    : *RedisConn c ?? cr { T x → x F e → { ( nurl_eprint `connect failed\n` ) ^ 1 } }

    // clean slate
    ?? ( redis_flushdb c ) { T _ → {} F _ → {} }

    // PING
    ?? ( redis_ping c ) { T b → ( __ok `ping` b ) F _ → ( __ok `ping` F ) }

    // SET / GET
    ?? ( redis_set c `k1` `v1` ) { T _ → {} F _ → {} }
    ?? ( redis_get c `k1` ) {
        T rs → { ( __ok `get k1=v1` & ! ( redis_str_is_nil rs ) != ( nurl_str_eq ( redis_str_val rs ) `v1` ) 0 ) ( redis_str_free rs ) }
        F _ → ( __ok `get k1=v1` F )
    }

    // GET missing → nil
    ?? ( redis_get c `missing` ) {
        T rs → { ( __ok `get missing nil` ( redis_str_is_nil rs ) ) ( redis_str_free rs ) }
        F _ → ( __ok `get missing nil` F )
    }

    // INCR twice
    ?? ( redis_incr c `cnt` ) { T n → ( __ok `incr→1` == n 1 ) F _ → ( __ok `incr→1` F ) }
    ?? ( redis_incr c `cnt` ) { T n → ( __ok `incr→2` == n 2 ) F _ → ( __ok `incr→2` F ) }

    // list
    ?? ( redis_rpush c `lst` `a` ) { T _ → {} F _ → {} }
    ?? ( redis_rpush c `lst` `b` ) { T _ → {} F _ → {} }
    ?? ( redis_rpush c `lst` `c` ) { T _ → {} F _ → {} }
    ?? ( redis_lrange c `lst` 0 -1 ) {
        T v → {
            : b ok3 == ( vec_len [String] v ) 3
            : b first & ok3 != ( nurl_str_eq ( string_data ?? ( vec_get [String] v 0 ) { T s → s F _ → ( string_new ) } ) `a` ) 0
            ( __ok `lrange [a,b,c]` first )
            ( __free_strvec v )
        }
        F _ → ( __ok `lrange [a,b,c]` F )
    }
    ?? ( redis_llen c `lst` ) { T n → ( __ok `llen 3` == n 3 ) F _ → ( __ok `llen 3` F ) }

    // hash
    ?? ( redis_hset c `h` `f1` `v1` ) { T _ → {} F _ → {} }
    ?? ( redis_hget c `h` `f1` ) {
        T rs → { ( __ok `hget f1=v1` != ( nurl_str_eq ( redis_str_val rs ) `v1` ) 0 ) ( redis_str_free rs ) }
        F _ → ( __ok `hget f1=v1` F )
    }
    ?? ( redis_hgetall c `h` ) {
        T v → { ( __ok `hgetall 2` == ( vec_len [String] v ) 2 ) ( __free_strvec v ) }
        F _ → ( __ok `hgetall 2` F )
    }

    // set
    ?? ( redis_sadd c `st` `m1` ) { T _ → {} F _ → {} }
    ?? ( redis_sadd c `st` `m2` ) { T _ → {} F _ → {} }
    ?? ( redis_smembers c `st` ) {
        T v → { ( __ok `smembers 2` == ( vec_len [String] v ) 2 ) ( __free_strvec v ) }
        F _ → ( __ok `smembers 2` F )
    }

    // DEL / EXISTS
    ?? ( redis_del c `k1` ) { T n → ( __ok `del 1` == n 1 ) F _ → ( __ok `del 1` F ) }
    ?? ( redis_exists c `k1` ) { T b → ( __ok `exists false` ! b ) F _ → ( __ok `exists false` F ) }

    // EXPIRE / TTL
    ?? ( redis_expire c `cnt` 100 ) { T b → ( __ok `expire ok` b ) F _ → ( __ok `expire ok` F ) }
    ?? ( redis_ttl c `cnt` ) { T n → ( __ok `ttl>0` > n 0 ) F _ → ( __ok `ttl>0` F ) }

    // error reply surfaces as RedisServerError
    ?? ( redis_incr c `lst` ) {
        T _ → ( __ok `wrongtype err` F )
        F e → ( __ok `wrongtype err` ?? e { RedisServerError → T _ → F } )
    }

    // pub/sub: subscribe on a second connection, publish on the first
    ?? ( redis_connect `127.0.0.1` 16379 ) {
        F _ → ( __ok `pubsub connect` F )
        T sub → {
            ?? ( redis_subscribe sub `news` ) {
                T m → { ( __ok `subscribe confirm` == ( redis_message_kind m ) 1 ) ( redis_message_free m ) }
                F _ → ( __ok `subscribe confirm` F )
            }
            ?? ( redis_publish c `news` `hello-pubsub` ) {
                T n → ( __ok `publish reached 1` == n 1 ) F _ → ( __ok `publish reached 1` F )
            }
            ?? ( redis_next_message sub ) {
                T m → {
                    ( __ok `message kind` == ( redis_message_kind m ) 0 )
                    ( __ok `message payload` != ( nurl_str_eq ( redis_message_payload m ) `hello-pubsub` ) 0 )
                    ( __ok `message channel` != ( nurl_str_eq ( redis_message_channel m ) `news` ) 0 )
                    ( redis_message_free m )
                }
                F _ → ( __ok `message kind` F )
            }
            ( redis_close sub )
        }
    }

    ( redis_close c )

    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 } { ( nurl_print `\nFAILED\n` ) ^ 1 }
}
