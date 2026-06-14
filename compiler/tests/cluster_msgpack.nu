// cluster_msgpack.nu — offline test for the msgpack wire format of
// stdlib/ext/cluster.nu. No sockets: drives the full envelope path
// (request → msgpack → dispatch → response → msgpack) in process. Uses a
// value above 2^31 (3000000000) so any signedness error in the binary
// int codec corrupts the round trip and fails the golden.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/cluster.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `true\n` `false\n` ) }

@ main → i {
    // ── wire toggle ──────────────────────────────────────────────
    ( pb `default msgpack: ` ( cluster_wire_is_msgpack ) )
    ( cluster_use_msgpack T )
    ( pb `after toggle: ` ( cluster_wire_is_msgpack ) )

    // ── registry with an echo handler ────────────────────────────
    : Registry reg ( registry_new )
    ( registry_register reg `echo`
    \ Json a → !Json ClusterErr { ^ @ !Json ClusterErr { T ( json_clone a ) } } )

    // ── request envelope { fn: echo, args: 3000000000 } ──────────
    : Json req ( json_obj_new )
    ( json_obj_set req `fn` ( json_str_lit `echo` ) )
    ( json_obj_set req `args` ( json_int 3000000000 ) )

    // request → msgpack → decode (the wire the server receives)
    : !( Vec u ) MsgpackErr renc ( msgpack_encode req )
    ( json_free req )
    ?? renc {
        T rbytes → {
            ( nurl_print `req wire bytes: ` ) ( nurl_print_int ( vec_len [u] rbytes ) )
            : !Json MsgpackErr rdec ( msgpack_decode rbytes )
            ( vec_free [u] rbytes )
            ?? rdec {
                T reqj → {
                    // dispatch → response envelope { ok, result }
                    : Json env ( rpc_dispatch reg reqj )
                    ( json_free reqj )
                    // response → msgpack → decode (the wire the client receives)
                    : !( Vec u ) MsgpackErr eenc ( msgpack_encode env )
                    ( json_free env )
                    ?? eenc {
                        T ebytes → {
                            : !Json MsgpackErr edec ( msgpack_decode ebytes )
                            ( vec_free [u] ebytes )
                            ?? edec {
                                T env2 → {
                                    : ?Json rj ( json_obj_get env2 `result` )
                                    ?? rj {
                                        T rv → {
                                            ( nurl_print `result: ` )
                                            ( nurl_print_int ( json_as_int rv ) )
                                        }
                                        F → ( nurl_print `no result\n` )
                                    }
                                    ( json_free env2 )
                                }
                                F → ( nurl_print `resp decode err\n` )
                            }
                        }
                        F → ( nurl_print `resp encode err\n` )
                    }
                }
                F → ( nurl_print `req decode err\n` )
            }
        }
        F → ( nurl_print `req encode err\n` )
    }

    ( registry_free reg )
    ^ 0
}
