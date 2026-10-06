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

// Capability bits a worker advertises in HELLO. cap_gpu: the worker runs wasm
// chunks with GPU host imports enabled (nwasm --allow-gpu on real hardware).
@ cap_gpu → i { ^ 1 }

// HELLO wire: [3][id:8][role:1][want:1][pklen:2][pubkey…][caps:1]
// The caps byte TRAILS the pubkey so a pre-caps decoder (fixed prefix +
// pklen-delimited pubkey) reads the same fields and ignores the tail; a caps
// decoder treats a missing tail as caps=0. Mixed-version clusters stay sound.
@ hello_build i id i role i want ( Vec u ) pubkey i caps → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u ( census_hello_t ) )
    ( bytes_push_u64_be b # u64 id )
    ( vec_push [u] b # u role )
    ( vec_push [u] b # u want )
    ( bytes_push_u16_be b # u16 ( vec_len [u] pubkey ) )
    ( vec_extend [u] b pubkey )
    ( vec_push [u] b # u caps )
    ^ b
}

: Hello { i id i role i want ( Vec u ) pubkey i caps }

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
    : i caps ?? ( vec_get [u] buf + 13 pklen ) { T x → # i x F → 0 }
    ^ @ Hello { id role want pk caps }
}

// ── membership set: the pubkeys currently in the ring ──────────────
// A node tracks the pubkeys it has folded into its ring so a re-heard HELLO is
// idempotent (adding a member twice would double its ring points and skew load).

// `last_ms` is when this member's HELLO was last heard. Workers re-announce on
// a ~2 s heartbeat, so a member silent far longer than that is gone: without
// this the ring kept a dead worker forever and every later submit paid a full
// round of chunk re-dispatches routing at a node that is never coming back.
// Eviction is self-healing — a worker that comes back re-announces and rejoins.
: Member { ( Vec u ) pubkey i id i caps i last_ms }

: RosterImpl { ( Vec Member ) members }

// A Roster is a handle on its member list in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same roster, and the last owner releases it.
: Roster { s ctl }

unsafe

@ Roster_share Roster h → Roster { ^ @ Roster { # s ( rcbox_share # i . h ctl ) } }

@ Roster_drop sink Roster h → v {
    ( mem_forget h )
    ( rcbox_release [RosterImpl] # i . h ctl )
}

unsafe

@ __Roster_ptr Roster h → *RosterImpl { ^ ( rcbox_ptr [RosterImpl] # i . h ctl ) }

unsafe

@ roster_new → Roster {
    ^ @ Roster { # s ( rcbox_new [RosterImpl] @ RosterImpl { ( vec_new [Member] ) } ) }
}

// Let go of `r` now rather than at the end of its owner's scope (optional).
@ roster_free sink Roster r → v {}

// Index of the member with `pubkey`, -1 if none.
unsafe

@ __roster_find * RosterImpl r ( Vec u ) pubkey → i {
    : i n ( vec_len [Member] . r members )
    : ~ i found -1 : ~ i k 0
    ~ & == found -1 < k n {
        ?? ( vec_get [Member] . r members k ) { T m → { ? ( bytes_eq . m pubkey pubkey ) { = found k } {} } F → {} }
        = k + k 1
    }
    ^ found
}

@ roster_has Roster r__h ( Vec u ) pubkey → b {
    : *RosterImpl r ( __Roster_ptr r__h )
    ^ >= ( __roster_find r pubkey ) 0
}

unsafe

@ roster_count Roster r__h → i {
    : *RosterImpl r ( __Roster_ptr r__h )
    ^ ( vec_len [Member] . r members )
}

// How many members advertise every capability bit in `mask`.
unsafe

@ roster_count_caps Roster r__h i mask → i {
    : *RosterImpl r ( __Roster_ptr r__h )
    : i n ( vec_len [Member] . r members )
    : ~ i c 0 : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Member] . r members k ) { T m → { ? == & . m caps mask mask { = c + c 1 } {} } F → {} }
        = k + k 1
    }
    ^ c
}

// Fold a worker into the roster + ring, once. Returns T if newly added.
// `now` is the caller's clock (ms); the member's liveness stamp starts there.
unsafe

@ roster_add Roster r__h Ring ring ( Vec u ) pubkey i id i vnodes i caps i now → b {
    : *RosterImpl r ( __Roster_ptr r__h )
    ? >= ( __roster_find r pubkey ) 0 { ^ F } {}
    : ( Vec u ) cp ( vec_with_cap [u] ( vec_len [u] pubkey ) )
    ( vec_extend [u] cp pubkey )
    ( vec_push [Member] . r members @ Member { cp id caps now } )
    ( ring_add_member ring pubkey vnodes )
    ^ T
}

// Refresh a member's liveness stamp (a re-heard HELLO). Unknown pubkey: no-op.
// The stamp is written in place, through the element's slot.
unsafe

@ roster_touch Roster r__h ( Vec u ) pubkey i now → v {
    : *RosterImpl r ( __Roster_ptr r__h )
    : i k ( __roster_find r pubkey )
    ? < k 0 { ^ v } {}
    : *Member m # *Member + # i ( vec_data [Member] . r members ) * k Z Member
    = . m last_ms now
}

// Drop every member silent for longer than `ttl_ms` and return their pubkeys
// (owned by the caller, which also removes them from its rings). The roster
// entry — not the ring — is the source of truth for who is live, so callers
// must apply the returned removals to every ring they maintain.
//
// `exempt` is never evicted (pass a node's own pubkey, empty for none): a
// worker hears no HELLO of its own, so without the exemption it would time
// itself out of its own ring and stop owning — and therefore stop executing —
// every key it holds.
unsafe

@ roster_expire Roster r__h i now i ttl_ms ( Vec u ) exempt → ( Vec ( Vec u ) ) {
    : *RosterImpl r ( __Roster_ptr r__h )
    : ( Vec ( Vec u ) ) gone ( vec_new [( Vec u )] )
    // An evicted member leaves the list (vec_remove hands it over, in order);
    // its pubkey moves into `gone`.
    : ~ i k 0
    ~ < k ( vec_len [Member] . r members ) {
        : b evict ?? ( vec_get [Member] . r members k ) { T m → & > - now . m last_ms ttl_ms ! ( bytes_eq . m pubkey exempt ) F → F }
        ? evict {
            ?? ( vec_remove [Member] . r members k ) { T m → { ( vec_push [( Vec u )] gone . m pubkey ) } F → {} }
        } { = k + k 1 }
    }
    ^ gone
}

// True when `pubkey` is a live roster member (the coordinator's liveness test
// for the worker a chunk was routed to).
@ roster_is_live Roster r ( Vec u ) pubkey → b { ^ ( roster_has r pubkey ) }

// Read-only view of member k: its node id, capability bits and last-heard
// stamp. Out of range → id 0. Used by the status tool, so an operator (or the
// model) can see the cluster the coordinator believes it has.
: MemberView { i id i caps i last_ms }

unsafe

@ roster_view Roster r__h i k → MemberView {
    : *RosterImpl r ( __Roster_ptr r__h )
    ^ ?? ( vec_get [Member] . r members k ) { T m → @ MemberView { . m id . m caps . m last_ms } F → @ MemberView { 0 0 0 } }
}
