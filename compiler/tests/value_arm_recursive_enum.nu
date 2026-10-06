// value_arm_recursive_enum.nu — an arm whose value is an owned recursive enum
// (Json: strings, Vecs of Json) drops its locals.
//
// `^ ? c { … } { : ?Json envo ( dec ) : !Json E out ?? envo { … } out }`: the
// check that the arm's value cannot point into its locals gave up on Json,
// a type reached again through its own payloads, so the decoded envelope
// leaked on every RPC (stdlib cluster's __rpc_attempt).

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: | CE { CBad CNet }

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ dec i k → ?Json { ? < k 0 { ^ @ ?Json { F } } {} ^ ?? ( json_parse `{"result":{"x":1}}` ) { T j → @ ?Json { T j } F _ → @ ?Json { F } } }

@ extract Json env → !Json CE {
    ?? ( json_get env `result` ) { T r → { ^ @ !Json CE { T ( json_clone r ) } } F → {} }
    ^ @ !Json CE { F CBad }
}

@ a i k → !Json CE {
    ^ ? < k -5 { @ !Json CE { F CBad } } {
        : ?Json envo ( dec k )
        : !Json CE out ?? envo {
            T env → {
                : !Json CE r2 ( extract env )
                r2
            }
            F → @ !Json CE { F CBad }
        }
        out
    }
}

@ main → i {
    : i l0 ( live )
    : ~ i k 0
    ~ < k 10 { : !Json CE r ( a k ) = k + k 1 }
    ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
