// cluster_rpc.nu — offline tests for stdlib/ext/cluster.nu.
//
// No sockets: exercises the registry + the pure `rpc_dispatch` path
// (request envelope → response envelope) end to end, plus the error
// name table. The HTTP transport is covered by examples/cluster_rpc.nu.
//
// Exercises:
//   * registry_register + registry_count
//   * rpc_dispatch hit  → { ok: true,  result: 49 }   (square of 7)
//   * rpc_dispatch miss → { ok: false, error: "no such fn" }
//   * cluster_err_name renders every variant

$ `stdlib/ext/cluster.nu`

// A registered handler: receives a BORROWED args Json (a number),
// returns an OWNED Json carrying its square.
@ h_square Json args → !Json ClusterErr {
    : ?i ni ( json_num_as_i args )
    ^ ?? ni {
        T n → @ !Json ClusterErr { T ( json_int * n n ) }
        F → @ !Json ClusterErr { F @ ClusterErr { ClSerialize } }
    }
}

@ print_ok Json env → v {
    : ?Json okj ( json_obj_get env `ok` )
    ?? okj {
        T b → ( nurl_print ? ( json_bool_val b ) `true` `false` )
        F → ( nurl_print `?` )
    }
}

@ main → i {
    : Registry reg ( registry_new )
    ( registry_register reg `square`
    \ Json a → !Json ClusterErr { ^ ( h_square a ) } )

    ( nurl_print `count: ` )
    ( nurl_println_int ( registry_count reg ) )

    // ── 1. Hit: square of 7 → 49 ─────────────────────────────────
    : Json req ( json_obj_new )
    ( json_obj_set req `fn` ( json_str_lit `square` ) )
    ( json_obj_set req `args` ( json_int 7 ) )
    : Json env ( rpc_dispatch reg req )
    ( json_free req )

    ( nurl_print `ok: ` )
    ( print_ok env )
    ( nurl_print `\n` )
    : ?Json resj ( json_obj_get env `result` )
    ?? resj {
        T rj → {
            ( nurl_print `result: ` )
            ( nurl_println_int ( json_as_int rj ) )
        }
        F → {}
    }
    ( nurl_print `\n` )
    ( json_free env )

    // ── 2. Miss: unknown fn → ok:false, error ────────────────────
    : Json req2 ( json_obj_new )
    ( json_obj_set req2 `fn` ( json_str_lit `nope` ) )
    ( json_obj_set req2 `args` ( json_null ) )
    : Json env2 ( rpc_dispatch reg req2 )
    ( json_free req2 )

    ( nurl_print `miss ok: ` )
    ( print_ok env2 )
    ( nurl_print `\n` )
    : ?Json errj ( json_obj_get env2 `error` )
    ?? errj {
        T ej → {
            ( nurl_print `err: ` )
            ( nurl_print ( json_as_str ej ) )
        }
        F → {}
    }
    ( nurl_print `\n` )
    ( json_free env2 )

    // ── 3. cluster_err_name renders every variant ────────────────
    ( nurl_println ( cluster_err_name # ClusterErr ClNet ) )
    ( nurl_println ( cluster_err_name # ClusterErr ClTimeout ) )
    ( nurl_println ( cluster_err_name # ClusterErr ClNoSuchFn ) )
    ( nurl_println ( cluster_err_name # ClusterErr ClBadResp ) )
    ( nurl_println ( cluster_err_name # ClusterErr ClRemote ) )
    ( nurl_println ( cluster_err_name # ClusterErr ClSerialize ) )

    ( registry_free reg )
    ^ 0
}
