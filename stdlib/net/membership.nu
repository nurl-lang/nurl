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

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/lifeguard.nu`

// ── member state ─────────────────────────────────────────────────
@ pk_alive   → i { ^ 0 }
@ pk_suspect → i { ^ 1 }
@ pk_dead    → i { ^ 2 }

: PkMember {
    ( Vec u ) pubkey
    i state          // 0 alive, 1 suspect, 2 dead
    i incarnation
    i last_ns        // last time we heard about this member (mono ns)
    i susp_start_ns  // when suspicion began (state == suspect)
    i susp_confirms  // independent suspicion confirmations
}

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

: PkMemberTable {
    ( Vec u ) self_pk
    i self_incarnation
    ( Vec s ) members        // *PkMember (excludes self)
    LocalHealth health
    i suspect_min_ns         // Lifeguard suspicion floor (corroborated)
    i suspect_max_ns         // Lifeguard suspicion ceiling (lone)
    i suspect_k              // confirmations to reach the floor
    i rr                     // round-robin probe cursor
}

@ pktable_new ( Vec u ) self_pk i suspect_min_ns i suspect_max_ns i suspect_k i lhm_max → *PkMemberTable {
    : *PkMemberTable t # *PkMemberTable ( nurl_alloc Z PkMemberTable )
    = . t self_pk ( __pk_cpy self_pk )
    = . t self_incarnation 0
    = . t members ( vec_new [s] )
    = . t health ( local_health_new lhm_max )
    = . t suspect_min_ns suspect_min_ns
    = . t suspect_max_ns suspect_max_ns
    = . t suspect_k suspect_k
    = . t rr 0
    ^ t
}

@ pktable_free *PkMemberTable t → v {
    ( vec_free [u] . t self_pk )
    : i n ( vec_len [s] . t members )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . t members k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *PkMember m # *PkMember pp ( vec_free [u] . m pubkey ) ( nurl_free # s m ) } {}
        = k + k 1
    }
    ( vec_free [s] . t members )
    ( nurl_free # s t )
}

@ pktable_count *PkMemberTable t → i { ^ ( vec_len [s] . t members ) }
@ lh_value_of *PkMemberTable t → i { ^ ( lh_value . t health ) }

@ __pk_find *PkMemberTable t ( Vec u ) pk → s {
    : i n ( vec_len [s] . t members )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . t members k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PkMember m # *PkMember pp
            ? ( __pk_veq . m pubkey pk ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

// Look up a member's current state (-1 if unknown / self).
@ pktable_state_of *PkMemberTable t ( Vec u ) pk → i {
    : s pp ( __pk_find t pk )
    ? == # i pp 0 { ^ - 0 1 } {}
    : *PkMember m # *PkMember pp
    ^ . m state
}

// Merge a (gossiped or observed) member fact with SWIM precedence:
//   * a strictly higher incarnation always wins (and resets suspicion);
//   * at equal incarnation, a WORSE state wins (alive < suspect < dead).
// Self facts are ignored here (handled via refutation). Returns T if changed.
@ pktable_apply *PkMemberTable t ( Vec u ) pk i nst i inc i now_ns → b {
    ? ( __pk_veq pk . t self_pk ) { ^ F } {}
    : s pp ( __pk_find t pk )
    ? == # i pp 0 {
        : *PkMember m # *PkMember ( nurl_alloc Z PkMember )
        = . m pubkey ( __pk_cpy pk )
        = . m state nst
        = . m incarnation inc
        = . m last_ns now_ns
        = . m susp_start_ns ? == nst 1 now_ns 0
        = . m susp_confirms 0
        ( vec_push [s] . t members # s m )
        ^ T
    } {}
    : *PkMember m # *PkMember pp
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
@ pktable_suspect *PkMemberTable t ( Vec u ) pk i now_ns → b {
    : s pp ( __pk_find t pk )
    ? == # i pp 0 { ^ F } {}
    : *PkMember m # *PkMember pp
    ? == . m state 0 {
        = . m state 1
        = . m susp_start_ns now_ns
        = . m susp_confirms 0
        ^ T
    } {}
    ^ F
}

// Another node independently confirms a suspicion → converge to dead faster.
@ pktable_confirm_suspect *PkMemberTable t ( Vec u ) pk → b {
    : s pp ( __pk_find t pk )
    ? == # i pp 0 { ^ F } {}
    : *PkMember m # *PkMember pp
    ? == . m state 1 {
        ? < . m susp_confirms . t suspect_k { = . m susp_confirms + . m susp_confirms 1 } {}
        ^ T
    } {}
    ^ F
}

// Refute a suspicion locally (we heard from the member). Returns to alive.
@ pktable_alive *PkMemberTable t ( Vec u ) pk i inc i now_ns → b {
    ^ ( pktable_apply t pk ( pk_alive ) inc now_ns )
}

// A first-hand observation that a member is alive (we got a direct ack from
// it). Authoritative for suspect→alive locally without needing a higher
// incarnation; does NOT revive a dead member (that requires gossip carrying
// a higher incarnation). Returns T if the member was revived from suspect.
@ pktable_observe_alive *PkMemberTable t ( Vec u ) pk i now_ns → b {
    : s pp ( __pk_find t pk )
    ? == # i pp 0 { ^ F } {}
    : *PkMember m # *PkMember pp
    = . m last_ns now_ns
    ? == . m state 1 {
        = . m state 0
        = . m susp_start_ns 0
        = . m susp_confirms 0
        ^ T
    } {}
    ^ F
}

// The effective suspicion deadline for a member, with the Lifeguard
// confirmation scaling AND this node's local-health scaling applied.
@ __pk_suspicion *PkMemberTable t *PkMember m → Suspicion {
    : i smin ( lh_scale . t health . t suspect_min_ns )
    : i smax ( lh_scale . t health . t suspect_max_ns )
    : Suspicion s ( suspicion_new smin smax . t suspect_k . m susp_start_ns )
    : ~ Suspicion sc s
    : ~ i c 0
    ~ < c . m susp_confirms { = sc ( suspicion_confirm sc ) = c + c 1 }
    ^ sc
}

// Promote any suspected member whose suspicion has expired to dead. Returns
// the newly-dead members as BORROWED *PkMember pointers into the table (the
// table still owns them) — read . m pubkey / . m incarnation, then free only
// the returned container with __pk_dead_free.
@ pktable_sweep *PkMemberTable t i now_ns → ( Vec s ) {
    : ( Vec s ) dead ( vec_new [s] )
    : i n ( vec_len [s] . t members )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . t members k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PkMember m # *PkMember pp
            ? == . m state 1 {
                : Suspicion s ( __pk_suspicion t m )
                ? ( suspicion_expired s now_ns ) {
                    = . m state 2
                    ( vec_push [s] dead pp )
                } {}
            } {}
        } {}
        = k + k 1
    }
    ^ dead
}

// Free only the container returned by pktable_sweep (members stay owned by
// the table).
@ __pk_dead_free ( Vec s ) dead → v { ( vec_free [s] dead ) }

// Round-robin pick an alive member to probe (its pubkey, copied). None if no
// alive members. Advances the cursor.
@ pktable_pick_probe *PkMemberTable t → ?( Vec u ) {
    : i n ( vec_len [s] . t members )
    ? == n 0 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ~ ?( Vec u ) out @ ?( Vec u ) { F # ( Vec u ) 0 }
    : ~ b got F
    : ~ i tries 0
    ~ & ! got < tries n {
        : i idx % + . t rr tries n
        : s pp ?? ( vec_get [s] . t members idx ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PkMember m # *PkMember pp
            ? == . m state 0 {
                = out @ ?( Vec u ) { T ( __pk_cpy . m pubkey ) }
                = . t rr % + idx 1 n
                = got T
            } {}
        } {}
        = tries + tries 1
    }
    ^ out
}

// Pick up to k alive members (excluding `exclude`) to relay an indirect
// ping-req through. Returns BORROWED *PkMember pointers into the table.
@ pktable_pick_relays *PkMemberTable t i k ( Vec u ) exclude → ( Vec s ) {
    : ( Vec s ) out ( vec_new [s] )
    : i n ( vec_len [s] . t members )
    : ~ i idx 0
    ~ & < idx n < ( vec_len [s] out ) k {
        : s pp ?? ( vec_get [s] . t members idx ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PkMember m # *PkMember pp
            ? & == . m state 0 ! ( __pk_veq . m pubkey exclude ) { ( vec_push [s] out pp ) } {}
        } {}
        = idx + idx 1
    }
    ^ out
}

// Health hooks: a probe that got an ack rewards local health; a fully failed
// probe (no direct or indirect ack) penalizes it (we might be the problem).
@ pktable_on_probe_ok *PkMemberTable t → v { = . t health ( lh_award . t health ) }
@ pktable_on_probe_fail *PkMemberTable t → v { = . t health ( lh_penalize . t health ) }

// ── gossip message codec ─────────────────────────────────────────
@ pk_ping    → i { ^ 1 }
@ pk_ack     → i { ^ 2 }
@ pk_pingreq → i { ^ 3 }

: PkMsg {
    i mtype
    i seq
    ( Vec u ) target     // ping-req: pubkey to probe (empty otherwise)
    ( Vec s ) gossip     // *PkMember snapshots piggybacked
}
@ pkmsg_free PkMsg m → v {
    ( vec_free [u] . m target )
    : i n ( vec_len [s] . m gossip )
    : ~ i k 0
    ~ < k n { : s pp ?? ( vec_get [s] . m gossip k ) { T x → x F → # s 0 } ? != # i pp 0 { : *PkMember mm # *PkMember pp ( vec_free [u] . mm pubkey ) ( nurl_free # s mm ) } {} = k + k 1 }
    ( vec_free [s] . m gossip )
}

// wire: [mtype:1][seq:4][tlen:2][target][gcount:2]
//       [ pklen:2 pubkey  state:1  inc:4 ]*       (gossip entries)
@ pkmsg_encode PkMsg m → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u . m mtype )
    ( bytes_push_u32_be b # u32 . m seq )
    ( bytes_push_u16_be b # u16 ( vec_len [u] . m target ) )
    ( vec_extend [u] b . m target )
    : i gn ( vec_len [s] . m gossip )
    ( bytes_push_u16_be b # u16 gn )
    : ~ i k 0
    ~ < k gn {
        : s pp ?? ( vec_get [s] . m gossip k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PkMember mm # *PkMember pp
            ( bytes_push_u16_be b # u16 ( vec_len [u] . mm pubkey ) )
            ( vec_extend [u] b . mm pubkey )
            ( vec_push [u] b # u . mm state )
            ( bytes_push_u32_be b # u32 . mm incarnation )
        } {}
        = k + k 1
    }
    ^ b
}

: PkCur { ( Vec u ) buf  i off }
@ __pkc_u8 *PkCur c → i { : i v ?? ( vec_get [u] . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 1 ^ v }
@ __pkc_u16 *PkCur c → i { : i v ?? ( bytes_read_u16_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 2 ^ v }
@ __pkc_u32 *PkCur c → i { : i v ?? ( bytes_read_u32_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 4 ^ v }
@ __pkc_take *PkCur c i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [u] . c buf + . c off k ) { T b → ( vec_push [u] o b ) F → {} } = k + k 1 }
    = . c off + . c off n
    ^ o
}

@ pkmsg_decode ( Vec u ) buf → PkMsg {
    : *PkCur c # *PkCur ( nurl_alloc Z PkCur )
    = . c buf buf
    = . c off 0
    : i mtype ( __pkc_u8 c )
    : i seq ( __pkc_u32 c )
    : i tlen ( __pkc_u16 c )
    : ( Vec u ) target ( __pkc_take c tlen )
    : i gn ( __pkc_u16 c )
    : ( Vec s ) gossip ( vec_new [s] )
    : ~ i k 0
    ~ < k gn {
        : i plen ( __pkc_u16 c )
        : ( Vec u ) pk ( __pkc_take c plen )
        : i st ( __pkc_u8 c )
        : i inc ( __pkc_u32 c )
        : *PkMember mm # *PkMember ( nurl_alloc Z PkMember )
        = . mm pubkey pk
        = . mm state st
        = . mm incarnation inc
        = . mm last_ns 0
        = . mm susp_start_ns 0
        = . mm susp_confirms 0
        ( vec_push [s] gossip # s mm )
        = k + k 1
    }
    ( nurl_free # s c )
    ^ @ PkMsg { mtype seq target gossip }
}

// Build a gossip snapshot of up to `max` members (caller frees via the
// PkMsg). Each entry carries pubkey/state/incarnation.
@ pktable_gossip *PkMemberTable t i max → ( Vec s ) {
    : ( Vec s ) g ( vec_new [s] )
    : i n ( vec_len [s] . t members )
    : ~ i k 0
    ~ & < k n < ( vec_len [s] g ) max {
        : s pp ?? ( vec_get [s] . t members k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PkMember m # *PkMember pp
            : *PkMember c # *PkMember ( nurl_alloc Z PkMember )
            = . c pubkey ( __pk_cpy . m pubkey )
            = . c state . m state
            = . c incarnation . m incarnation
            = . c last_ns 0
            = . c susp_start_ns 0
            = . c susp_confirms 0
            ( vec_push [s] g # s c )
        } {}
        = k + k 1
    }
    ^ g
}

// Apply every member fact carried in a decoded message's gossip list.
@ pktable_apply_gossip *PkMemberTable t PkMsg m i now_ns → v {
    : i n ( vec_len [s] . m gossip )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . m gossip k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PkMember mm # *PkMember pp
            ( pktable_apply t . mm pubkey . mm state . mm incarnation now_ns )
        } {}
        = k + k 1
    }
}
