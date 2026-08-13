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

@ census_hello_t → i { ^ 3 }

@ role_client → i { ^ 0 }

@ role_worker → i { ^ 1 }

// Capability bits a worker advertises in HELLO. cap_gpu: the worker runs wasm
// chunks with GPU host imports enabled (wt --allow-gpu on real hardware).
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

@ hello_free Hello h → v { ( vec_free [u] . h pubkey ) }

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

: Roster { ( Vec s ) members }  // *Member

@ roster_new → *Roster {
    : *Roster r # *Roster ( nurl_alloc Z Roster )
    = . r members ( vec_new [s] )
    ^ r
}

@ roster_free * Roster r → v {
    : i n ( vec_len [s] . r members )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r members k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *Member m # *Member pp ( vec_free [u] . m pubkey ) ( nurl_free # s m ) } {}
        = k + k 1
    }
    ( vec_free [s] . r members )
    ( nurl_free # s r )
}

@ roster_has * Roster r ( Vec u ) pubkey → b {
    : i n ( vec_len [s] . r members )
    : ~ b found F : ~ i k 0
    ~ & ! found < k n {
        : s pp ?? ( vec_get [s] . r members k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *Member m # *Member pp ? ( bytes_eq . m pubkey pubkey ) { = found T } {} } {}
        = k + k 1
    }
    ^ found
}

@ roster_count * Roster r → i { ^ ( vec_len [s] . r members ) }

// How many members advertise every capability bit in `mask`.
@ roster_count_caps * Roster r i mask → i {
    : i n ( vec_len [s] . r members )
    : ~ i c 0 : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r members k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *Member m # *Member pp ? == & . m caps mask mask { = c + c 1 } {} } {}
        = k + k 1
    }
    ^ c
}

// Fold a worker into the roster + ring, once. Returns T if newly added.
// `now` is the caller's clock (ms); the member's liveness stamp starts there.
@ roster_add * Roster r * Ring ring ( Vec u ) pubkey i id i vnodes i caps i now → b {
    ? ( roster_has r pubkey ) { ^ F } {}
    : *Member m # *Member ( nurl_alloc Z Member )
    : ( Vec u ) cp ( vec_with_cap [u] ( vec_len [u] pubkey ) )
    ( vec_extend [u] cp pubkey )
    = . m pubkey cp
    = . m id id
    = . m caps caps
    = . m last_ms now
    ( vec_push [s] . r members # s m )
    ( ring_add_member ring pubkey vnodes )
    ^ T
}

// Refresh a member's liveness stamp (a re-heard HELLO). Unknown pubkey: no-op.
@ roster_touch * Roster r ( Vec u ) pubkey i now → v {
    : i n ( vec_len [s] . r members )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r members k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Member m # *Member pp
            ? ( bytes_eq . m pubkey pubkey ) { = . m last_ms now = k n } {}
        } {}
        = k + k 1
    }
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
@ roster_expire * Roster r i now i ttl_ms ( Vec u ) exempt → ( Vec ( Vec u ) ) {
    : ( Vec ( Vec u ) ) gone ( vec_new [( Vec u )] )
    : ( Vec s ) keep ( vec_new [s] )
    : i n ( vec_len [s] . r members )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r members k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Member m # *Member pp
            ? & > - now . m last_ms ttl_ms ! ( bytes_eq . m pubkey exempt ) {
                ( vec_push [( Vec u )] gone . m pubkey )
                ( nurl_free # s m )
            } { ( vec_push [s] keep pp ) }
        } {}
        = k + k 1
    }
    ( vec_free [s] . r members )
    = . r members keep
    ^ gone
}

// True when `pubkey` is a live roster member (the coordinator's liveness test
// for the worker a chunk was routed to).
@ roster_is_live * Roster r ( Vec u ) pubkey → b { ^ ( roster_has r pubkey ) }

// Read-only view of member k: its node id, capability bits and last-heard
// stamp. Out of range → id 0. Used by the status tool, so an operator (or the
// model) can see the cluster the coordinator believes it has.
: MemberView { i id i caps i last_ms }

@ roster_view * Roster r i k → MemberView {
    : i n ( vec_len [s] . r members )
    ? | < k 0 >= k n { ^ @ MemberView { 0 0 0 } } {}
    : s pp ?? ( vec_get [s] . r members k ) { T x → x F → # s 0 }
    ? == # i pp 0 { ^ @ MemberView { 0 0 0 } } {}
    : *Member m # *Member pp
    ^ @ MemberView { . m id . m caps . m last_ms }
}
