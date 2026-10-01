// packages/swarm/src/census.nu — lightweight membership gossip for the swarm.
//
// The compute layer (dist/job over dist/ring) needs every node to agree on the
// live worker set: a worker must know it owns a key, and the coordinator must
// know which pubkeys to route to. The full SWIM table (net/membership.nu) is
// the heavy, churn-hardened answer; this is the small one a compute cluster
// actually needs — a HELLO announcement that feeds the consistent-hash ring.
//
//   * a node joins by broadcasting HELLO(role, want=1) to the relay group;
//   * everyone who hears it adds the node to their ring (workers only) and, if
//     `want`, replies with their own HELLO so the newcomer learns them too;
//   * the ring converges, and "join the cluster" is literally "run the binary".
//
// Roles: a WORKER owns keys and executes handlers, so it joins everyone's ring;
// a CLIENT (the coordinator) only submits, so it is never added to the ring —
// otherwise it would own keys it has no handler for and silently drop results.
//
// The codec and the membership set are pure; only the pump touches transport.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/core/rcbox.nu`

@ census_hello_t → i { ^ 3 }

@ role_client → i { ^ 0 }

@ role_worker → i { ^ 1 }

// HELLO wire: [3][id:8][role:1][want:1][pklen:2][pubkey…]
@ hello_build i id i role i want ( Vec u ) pubkey → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u ( census_hello_t ) )
    ( bytes_push_u64_be b # u64 id )
    ( vec_push [u] b # u role )
    ( vec_push [u] b # u want )
    ( bytes_push_u16_be b # u16 ( vec_len [u] pubkey ) )
    ( vec_extend [u] b pubkey )
    ^ b
}

: Hello { i id i role i want ( Vec u ) pubkey }

// A Hello owns only its pubkey, which its owner drops; this lets go of it
// now rather than at the end of the owner's scope (optional).
@ hello_free sink Hello h → v {}

@ hello_decode ( Vec u ) buf → Hello {
    : i id ?? ( bytes_read_u64_be buf 1 ) { T x → # i x F → 0 }
    : i role ?? ( vec_get [u] buf 9 ) { T x → # i x F → 0 }
    : i want ?? ( vec_get [u] buf 10 ) { T x → # i x F → 0 }
    : i pklen ?? ( bytes_read_u16_be buf 11 ) { T x → # i x F → 0 }
    : ( Vec u ) pk ( vec_with_cap [u] pklen )
    : ~ i k 0
    ~ < k pklen { ?? ( vec_get [u] buf + 13 k ) { T x → ( vec_push [u] pk x ) F → {} } = k + k 1 }
    ^ @ Hello { id role want pk }
}

// ── membership set: the pubkeys currently in the ring ──────────────
// A node tracks the pubkeys it has folded into its ring so a re-heard HELLO is
// idempotent (adding a member twice would double its ring points and skew load).

: Member { ( Vec u ) pubkey i id }

: RosterImpl { ( Vec Member ) members }

// A Roster is a handle on its member list in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same roster, and the last owner releases it.
: Roster { s ctl }

@ Roster_share Roster h → Roster { ^ @ Roster { # s ( rcbox_share # i . h ctl ) } }

@ Roster_drop sink Roster h → v {
    ( mem_forget h )
    ( rcbox_release [RosterImpl] # i . h ctl )
}

@ __Roster_ptr Roster h → *RosterImpl { ^ ( rcbox_ptr [RosterImpl] # i . h ctl ) }

@ roster_new → Roster {
    ^ @ Roster { # s ( rcbox_new [RosterImpl] @ RosterImpl { ( vec_new [Member] ) } ) }
}

// Let go of `r` now rather than at the end of its owner's scope (optional).
@ roster_free sink Roster r → v {}

@ roster_has Roster r__h ( Vec u ) pubkey → b {
    : *RosterImpl r ( __Roster_ptr r__h )
    : i n ( vec_len [Member] . r members )
    : ~ b found F : ~ i k 0
    ~ & ! found < k n {
        ?? ( vec_get [Member] . r members k ) { T m → { ? ( bytes_eq . m pubkey pubkey ) { = found T } {} } F → {} }
        = k + k 1
    }
    ^ found
}

@ roster_count Roster r__h → i {
    : *RosterImpl r ( __Roster_ptr r__h )
    ^ ( vec_len [Member] . r members )
}

// Fold a worker into the roster + ring, once. Returns T if newly added.
@ roster_add Roster r__h Ring ring ( Vec u ) pubkey i id i vnodes → b {
    ? ( roster_has r__h pubkey ) { ^ F } {}
    : *RosterImpl r ( __Roster_ptr r__h )
    : ( Vec u ) cp ( vec_with_cap [u] ( vec_len [u] pubkey ) )
    ( vec_extend [u] cp pubkey )
    ( vec_push [Member] . r members @ Member { cp id } )
    ( ring_add_member ring pubkey vnodes )
    ^ T
}
