// stdlib/net/membership.nu — pubkey-keyed SWIM membership for the overlay
// (§7.4 Phase 5). The §7.2 std/swim runs over raw UDP and keys members by
// host:port; over net/transport a member is a STATIC PUBLIC KEY whose
// endpoint roams, so this is a parallel membership layer keyed by pubkey and
// hardened for mobile/NAT links with the std/lifeguard mechanisms:
//
//   • suspect → dead uses a Lifeguard confirmation-scaled suspicion timeout
//     (lone suspicions wait long — a roaming blip — corroborated ones
//     converge fast), and that timeout is further scaled by this node's
//     Local Health Multiplier (a node on a bad link is slower to declare
//     anyone dead, killing false positives).
//
// This module is the membership STATE MACHINE + gossip wire codec, both pure
// and time-injected (every time-dependent call takes now_ns) → fully
// deterministic and offline-testable. The transport-driven probe loop
// (ping / ack / ping-req over net/transport) wires these onto the overlay
// and is exercised with the sim-NAT harness.
//
// A PkMemberTable is a handle: every copy (a failure detector's, a
// heartbeat loop's) is the same table, and its last owner releases it —
// pktable_free is an early release, optional. Members are PkMember values:
// the table keeps its own in a ( Vec PkMember ), and everything it hands out
// (pktable_gossip, pktable_sweep, pktable_pick_relays, pktable_self_fact) is
// an owned copy, as is a decoded PkMsg's gossip — dropping the Vec (or the
// PkMsg) releases them; pkmsg_free is an early release, optional.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/lifeguard.nu`
$ `stdlib/core/rcbox.nu`

// ── member state ─────────────────────────────────────────────────
@ pk_alive → i { ^ 0 }

@ pk_suspect → i { ^ 1 }

@ pk_dead → i { ^ 2 }

: PkMember {
    ( Vec u ) pubkey
    i state  // 0 alive, 1 suspect, 2 dead
    i incarnation
    i last_ns  // last time we heard about this member (mono ns)
    i susp_start_ns  // when suspicion began (state == suspect)
    i susp_confirms  // independent suspicion confirmations
}

// A member fact as gossip carries it: pubkey (copied), state, incarnation.
@ __pk_fact ( Vec u ) pk i st i inc → PkMember { ^ @ PkMember { ( __pk_cpy pk ) st inc 0 0 0 } }

// An owned copy of a member, every field.
@ __pk_snap * PkMember m → PkMember {
    ^ @ PkMember { ( __pk_cpy . m pubkey ) . m state . m incarnation . m last_ns . m susp_start_ns . m susp_confirms }
}

// The member at index k, in place: a view into the Vec's buffer, valid until
// the Vec grows (never held across a push). k is in range.
@ __pk_at ( Vec PkMember ) v i k → *PkMember { ^ # *PkMember + # i ( vec_data [PkMember] v ) * k Z PkMember }

@ __pk_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

@ __pk_veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

// ── member table ─────────────────────────────────────────────────

: PkMemberTableImpl {
    ( Vec u ) self_pk
    i self_incarnation
    ( Vec PkMember ) members  // excludes self
    LocalHealth health
    i suspect_min_ns  // Lifeguard suspicion floor (corroborated)
    i suspect_max_ns  // Lifeguard suspicion ceiling (lone)
    i suspect_k  // confirmations to reach the floor
    i rr  // round-robin probe cursor
}

// A PkMemberTable is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: PkMemberTable { s ctl }

@ PkMemberTable_share PkMemberTable h → PkMemberTable { ^ @ PkMemberTable { # s ( rcbox_share # i . h ctl ) } }

@ PkMemberTable_drop sink PkMemberTable h → v {
    ( mem_forget h )
    ( rcbox_release [PkMemberTableImpl] # i . h ctl )
}

@ __PkMemberTable_ptr PkMemberTable h → *PkMemberTableImpl { ^ ( rcbox_ptr [PkMemberTableImpl] # i . h ctl ) }

@ pktable_new ( Vec u ) self_pk i suspect_min_ns i suspect_max_ns i suspect_k i lhm_max → PkMemberTable {
    : i t__box ( rcbox_zero [PkMemberTableImpl] )
    : *PkMemberTableImpl t ( rcbox_ptr [PkMemberTableImpl] t__box )
    = . t self_pk ( __pk_cpy self_pk )
    = . t self_incarnation 0
    = . t members ( vec_new [PkMember] )
    = . t health ( local_health_new lhm_max )
    = . t suspect_min_ns suspect_min_ns
    = . t suspect_max_ns suspect_max_ns
    = . t suspect_k suspect_k
    = . t rr 0
    ^ @ PkMemberTable { # s t__box }
}

// Let go of `t` now rather than at the end of its owner's scope.
@ pktable_free sink PkMemberTable t → v {}

@ pktable_count PkMemberTable t__h → i {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    ^ ( vec_len [PkMember] . t members )
}

@ lh_value_of PkMemberTable t__h → i {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    ^ ( lh_value . t health )
}

// Index of the member with pubkey pk, or -1.
@ __pk_find * PkMemberTableImpl t ( Vec u ) pk → i {
    : i n ( vec_len [PkMember] . t members )
    : ~ i found -1
    : ~ i k 0
    ~ & < found 0 < k n {
        : *PkMember m ( __pk_at . t members k )
        ? ( __pk_veq . m pubkey pk ) { = found k } {}
        = k + k 1
    }
    ^ found
}

// Look up a member's current state (-1 if unknown / self).
@ pktable_state_of PkMemberTable t__h ( Vec u ) pk → i {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : i idx ( __pk_find t pk )
    ? < idx 0 { ^ - 0 1 } {}
    : *PkMember m ( __pk_at . t members idx )
    ^ . m state
}

// Merge a (gossiped or observed) member fact with SWIM precedence:
//   * a strictly higher incarnation always wins (and resets suspicion);
//   * at equal incarnation, a WORSE state wins (alive < suspect < dead).
// Self facts are ignored here (handled via refutation). Returns T if changed.
@ pktable_apply PkMemberTable t__h ( Vec u ) pk i nst i inc i now_ns → b {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    ? ( __pk_veq pk . t self_pk ) { ^ F } {}
    : i idx ( __pk_find t pk )
    ? < idx 0 {
        : i susp ? == nst 1 now_ns 0
        ( vec_push [PkMember] . t members @ PkMember { ( __pk_cpy pk ) nst inc now_ns susp 0 } )
        ^ T
    } {}
    : *PkMember m ( __pk_at . t members idx )
    : ~ b changed F
    ? > inc . m incarnation {
        = . m incarnation inc
        = . m state nst
        = . m last_ns now_ns
        ? == nst 1 { = . m susp_start_ns now_ns = . m susp_confirms 0 } { = . m susp_start_ns 0 = . m susp_confirms 0 }
        = changed T
    } {
        ? & == inc . m incarnation > nst . m state {
            = . m state nst
            = . m last_ns now_ns
            ? == nst 1 { = . m susp_start_ns now_ns = . m susp_confirms 0 } {}
            = changed T
        } {}
    }
    ^ changed
}

// Begin suspecting an alive member (e.g. a probe went unanswered).
@ pktable_suspect PkMemberTable t__h ( Vec u ) pk i now_ns → b {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : i idx ( __pk_find t pk )
    ? < idx 0 { ^ F } {}
    : *PkMember m ( __pk_at . t members idx )
    ? == . m state 0 {
        = . m state 1
        = . m susp_start_ns now_ns
        = . m susp_confirms 0
        ^ T
    } {}
    ^ F
}

// Another node independently confirms a suspicion → converge to dead faster.
@ pktable_confirm_suspect PkMemberTable t__h ( Vec u ) pk → b {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : i idx ( __pk_find t pk )
    ? < idx 0 { ^ F } {}
    : *PkMember m ( __pk_at . t members idx )
    ? == . m state 1 {
        ? < . m susp_confirms . t suspect_k { = . m susp_confirms + . m susp_confirms 1 } {}
        ^ T
    } {}
    ^ F
}

// Refute a suspicion locally (we heard from the member). Returns to alive.
@ pktable_alive PkMemberTable t__h ( Vec u ) pk i inc i now_ns → b {
    ^ ( pktable_apply t__h pk ( pk_alive ) inc now_ns )
}

// A first-hand observation that a member is alive (we got a direct ack from
// it). Authoritative for suspect→alive locally without needing a higher
// incarnation; does NOT revive a dead member (that requires gossip carrying
// a higher incarnation). Returns T if the member was revived from suspect.
@ pktable_observe_alive PkMemberTable t__h ( Vec u ) pk i now_ns → b {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : i idx ( __pk_find t pk )
    ? < idx 0 { ^ F } {}
    : *PkMember m ( __pk_at . t members idx )
    = . m last_ns now_ns
    ? == . m state 1 {
        = . m state 0
        = . m susp_start_ns 0
        = . m susp_confirms 0
        ^ T
    } {}
    ^ F
}

// ── self liveness & refutation (§7.5 Phase 10) ──────────────────
// The non-obvious mobile/compute failure mode: a CPU-bound node misses pings,
// a peer suspects it, and the node doing real work gets ejected. Lifeguard's
// LHM protects the ACCUSER; these protect the busy ACCUSED. (Caveat per
// ASYNC.md: NURL fibers are cooperative — a handler that NEVER yields cannot
// run the heartbeat at all; the executor must yield between tasks. What this
// guarantees is that a node which yields even occasionally always wins back
// its liveness against a stale suspicion.)

@ pktable_self_incarnation PkMemberTable t__h → i {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    ^ . t self_incarnation
}

// Refute a suspicion of THIS node: bump our incarnation past `observed_inc`
// so the Alive fact our next heartbeat carries strictly outranks the stale
// Suspect/Dead and reinstates us everywhere. T if a bump happened.
@ pktable_refute PkMemberTable t__h i observed_inc → b {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    ? >= observed_inc . t self_incarnation {
        = . t self_incarnation + observed_inc 1
        ^ T
    } {}
    ^ F
}

// Proactive "alive-but-busy" heartbeat fact: an Alive self-fact at our
// current incarnation, to gossip so peers refresh our liveness without
// probing us (and, after a refute, to carry the higher incarnation that wins
// us back). An owned PkMember.
@ pktable_self_fact PkMemberTable t__h → PkMember {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    ^ ( __pk_fact . t self_pk ( pk_alive ) . t self_incarnation )
}

// The effective suspicion deadline for a member, with the Lifeguard
// confirmation scaling AND this node's local-health scaling applied.
@ __pk_suspicion * PkMemberTableImpl t * PkMember m → Suspicion {
    : i smin ( lh_scale . t health . t suspect_min_ns )
    : i smax ( lh_scale . t health . t suspect_max_ns )
    : Suspicion s ( suspicion_new smin smax . t suspect_k . m susp_start_ns )
    : ~ Suspicion sc s
    : ~ i c 0
    ~ < c . m susp_confirms { = sc ( suspicion_confirm sc ) = c + c 1 }
    ^ sc
}

// Promote any suspected member whose suspicion has expired to dead. Returns
// the newly-dead members as owned copies (pubkey / incarnation / …).
@ pktable_sweep PkMemberTable t__h i now_ns → ( Vec PkMember ) {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : ( Vec PkMember ) dead ( vec_new [PkMember] )
    : i n ( vec_len [PkMember] . t members )
    : ~ i k 0
    ~ < k n {
        : *PkMember m ( __pk_at . t members k )
        ? == . m state 1 {
            : Suspicion s ( __pk_suspicion t m )
            ? ( suspicion_expired s now_ns ) {
                = . m state 2
                ( vec_push [PkMember] dead ( __pk_snap m ) )
            } {}
        } {}
        = k + k 1
    }
    ^ dead
}

// Let go of pktable_sweep's result now rather than at the end of its
// owner's scope.
@ _pk_dead_free sink ( Vec PkMember ) dead → v {}

// Round-robin pick an alive member to probe (its pubkey, copied). None if no
// alive members. Advances the cursor.
@ pktable_pick_probe PkMemberTable t__h → ?( Vec u ) {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : i n ( vec_len [PkMember] . t members )
    ? == n 0 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ~ ? ( Vec u ) out @ ?( Vec u ) { F # ( Vec u ) 0 }
    : ~ b got F
    : ~ i tries 0
    ~ & ! got < tries n {
        : i idx % + . t rr tries n
        : *PkMember m ( __pk_at . t members idx )
        ? == . m state 0 {
            = out @ ?( Vec u ) { T ( __pk_cpy . m pubkey ) }
            = . t rr % + idx 1 n
            = got T
        } {}
        = tries + tries 1
    }
    ^ out
}

// Pick up to k alive members (excluding `exclude`) to relay an indirect
// ping-req through. Returns owned copies.
@ pktable_pick_relays PkMemberTable t__h i k ( Vec u ) exclude → ( Vec PkMember ) {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : ( Vec PkMember ) out ( vec_new [PkMember] )
    : i n ( vec_len [PkMember] . t members )
    : ~ i idx 0
    ~ & < idx n < ( vec_len [PkMember] out ) k {
        : *PkMember m ( __pk_at . t members idx )
        ? & == . m state 0 ! ( __pk_veq . m pubkey exclude ) { ( vec_push [PkMember] out ( __pk_snap m ) ) } {}
        = idx + idx 1
    }
    ^ out
}

// Health hooks: a probe that got an ack rewards local health; a fully failed
// probe (no direct or indirect ack) penalizes it (we might be the problem).
@ pktable_on_probe_ok PkMemberTable t__h → v {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    = . t health ( lh_award . t health )
}

@ pktable_on_probe_fail PkMemberTable t__h → v {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    = . t health ( lh_penalize . t health )
}

// ── gossip message codec ─────────────────────────────────────────
@ pk_ping → i { ^ 1 }

@ pk_ack → i { ^ 2 }

@ pk_pingreq → i { ^ 3 }

: PkMsg {
    i mtype
    i seq
    ( Vec u ) target  // ping-req: pubkey to probe (empty otherwise)
    ( Vec PkMember ) gossip  // member facts piggybacked (pubkey/state/incarnation)
}

// Let go of `m` now rather than at the end of its owner's scope.
@ pkmsg_free sink PkMsg m → v {}

// wire: [mtype:1][seq:4][tlen:2][target][gcount:2]
//       [ pklen:2 pubkey  state:1  inc:4 ]*       (gossip entries)
@ pkmsg_encode PkMsg m → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u . m mtype )
    ( bytes_push_u32_be b # u32 . m seq )
    ( bytes_push_u16_be b # u16 ( vec_len [u] . m target ) )
    ( vec_extend [u] b . m target )
    : i gn ( vec_len [PkMember] . m gossip )
    ( bytes_push_u16_be b # u16 gn )
    : ~ i k 0
    ~ < k gn {
        : *PkMember mm ( __pk_at . m gossip k )
        ( bytes_push_u16_be b # u16 ( vec_len [u] . mm pubkey ) )
        ( vec_extend [u] b . mm pubkey )
        ( vec_push [u] b # u . mm state )
        ( bytes_push_u32_be b # u32 . mm incarnation )
        = k + k 1
    }
    ^ b
}

// Readers over `b` at the cursor `off`, which they advance; a read past the
// end yields 0 (a take, the bytes that are there).
@ __pkc_u8 ( Vec u ) b inout i off → i { : i v ?? ( vec_get [u] b off ) { T x → # i x F → 0 } = off + off 1 ^ v }

@ __pkc_u16 ( Vec u ) b inout i off → i { : i v ?? ( bytes_read_u16_be b off ) { T x → # i x F → 0 } = off + off 2 ^ v }

@ __pkc_u32 ( Vec u ) b inout i off → i { : i v ?? ( bytes_read_u32_be b off ) { T x → # i x F → 0 } = off + off 4 ^ v }

@ __pkc_take ( Vec u ) b inout i off i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] n )
    ( vec_extend_range [u] o b off n )
    = off + off n
    ^ o
}

@ pkmsg_decode ( Vec u ) buf → PkMsg {
    : ~ i off 0
    : i mtype ( __pkc_u8 buf off )
    : i seq ( __pkc_u32 buf off )
    : i tlen ( __pkc_u16 buf off )
    : ( Vec u ) target ( __pkc_take buf off tlen )
    : i gn ( __pkc_u16 buf off )
    // An entry is at least 7 bytes on the wire: a count the rest of the
    // buffer cannot hold reserves no more than it could.
    : i room / - ( vec_len [u] buf ) off 7
    : ( Vec PkMember ) gossip ( vec_with_cap [PkMember] ? < room gn room gn )
    : ~ i k 0
    ~ < k gn {
        : i plen ( __pkc_u16 buf off )
        : ( Vec u ) pk ( __pkc_take buf off plen )
        : i st ( __pkc_u8 buf off )
        : i inc ( __pkc_u32 buf off )
        ( vec_push [PkMember] gossip @ PkMember { pk st inc 0 0 0 } )
        = k + k 1
    }
    ^ @ PkMsg { mtype seq target gossip }
}

// Build a gossip snapshot of up to `max` members (owned copies; put it in a
// PkMsg). Each entry carries pubkey/state/incarnation.
@ pktable_gossip PkMemberTable t__h i max → ( Vec PkMember ) {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : i n ( vec_len [PkMember] . t members )
    : ~ i gn n
    ? < max gn { = gn ? < max 0 0 max } {}
    : ( Vec PkMember ) g ( vec_with_cap [PkMember] gn )
    : ~ i k 0
    ~ < k gn {
        : *PkMember m ( __pk_at . t members k )
        ( vec_push [PkMember] g ( __pk_fact . m pubkey . m state . m incarnation ) )
        = k + k 1
    }
    ^ g
}

// Apply every member fact carried in a decoded message's gossip list.
@ pktable_apply_gossip PkMemberTable t__h PkMsg m i now_ns → v {
    : *PkMemberTableImpl t ( __PkMemberTable_ptr t__h )
    : i n ( vec_len [PkMember] . m gossip )
    : ~ i k 0
    ~ < k n {
        : *PkMember mm ( __pk_at . m gossip k )
        ? ( __pk_veq . mm pubkey . t self_pk ) {
            // Gossip about US. If a peer thinks we're suspect/dead (e.g. it
            // missed our pings while we were CPU-bound), REFUTE: bump our
            // incarnation past theirs so our next heartbeat reinstates us.
            ? != . mm state ( pk_alive ) { ( pktable_refute t__h . mm incarnation ) } {}
        } {
            ( pktable_apply t__h . mm pubkey . mm state . mm incarnation now_ns )
        }
        = k + k 1
    }
}
