// stdlib/std/swim.nu — SWIM cluster membership + failure detection.
//
// **Phase 2 (TODO §7.2)** of the distributed-computing track: replaces the
// static peer list with a self-maintaining membership view. Implements the
// SWIM protocol (Scalable Weakly-consistent Infection-style Membership):
//
//   * failure detection by periodic random PING, with INDIRECT pings
//     (PING-REQ via k random members) to suppress false positives from a
//     single lossy path;
//   * dissemination by gossip — membership changes piggyback on the
//     PING/ACK traffic, infecting the cluster epidemically;
//   * Alive → Suspect → Dead with INCARNATION numbers so a node can refute
//     a stale suspicion about itself.
//
// Layered so the bug-dense parts are deterministic and unit-tested offline:
//   1. wire codec   — SwimMsg ⇄ bytes (this file's first half)
//   2. member table — state machine + incarnation refutation + gossip merge
//   3. protocol     — the UDP I/O loop wiring 1+2 together
//
// Built on std/udp.nu (datagram transport) + std/bytes.nu (big-endian
// codec) + std/rng.nu (random member selection) + std/time.nu (timeouts).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/async.nu`

// ── Member state ─────────────────────────────────────────────────────

: | MemberState {
    MAlive
    MSuspect
    MDead
}

@ member_state_name MemberState s → s {
    ^ ?? s {
        MAlive → `alive`
        MSuspect → `suspect`
        MDead → `dead`
    }
}

@ __state_code MemberState s → i {
    ^ ?? s { MAlive → 0 MSuspect → 1 MDead → 2 }
}

@ __state_of i c → MemberState {
    ^ ? == c 0 @ MemberState { MAlive }
    ? == c 1 @ MemberState { MSuspect }
    @ MemberState { MDead }
}

// A cluster member. `incarnation` is the member's own logical clock; a
// higher incarnation always wins, which is how a node refutes a stale
// suspicion about itself. `last_change_ms` is a local monotonic stamp
// driving the suspicion → dead timeout.
: Member {
    String host
    i port
    i incarnation
    MemberState state
    i last_change_ms
}

@ member_new s host i port i incarnation MemberState state → Member {
    ^ @ Member { ( string_from host ) port incarnation state ( monotonic_ns ) }
}

@ member_free Member m → v {
    ( string_free . m host )
}

// ── Message types ────────────────────────────────────────────────────

: | SwimMsgType {
    MtPing
    MtAck
    MtPingReq  // indirect probe request: "please ping target for me"
    MtJoin
    MtJoinAck
}

@ __mtype_code SwimMsgType t → i {
    ^ ?? t { MtPing → 1 MtAck → 2 MtPingReq → 3 MtJoin → 4 MtJoinAck → 5 }
}

@ __mtype_of i c → SwimMsgType {
    ^ ? == c 1 @ SwimMsgType { MtPing }
    ? == c 2 @ SwimMsgType { MtAck }
    ? == c 3 @ SwimMsgType { MtPingReq }
    ? == c 4 @ SwimMsgType { MtJoin }
    @ SwimMsgType { MtJoinAck }
}

// A SWIM datagram. `seq` matches an ACK to its PING. `from_*` is the
// sender; `target_*` is the indirect-probe subject (PING-REQ only).
// `gossip` carries piggybacked membership updates (each a bare Member
// snapshot — host/port/incarnation/state).
: SwimMsg {
    SwimMsgType mtype
    i seq
    String from_host
    i from_port
    String target_host
    i target_port
    ( Vec Member ) gossip
}

@ swim_msg_free SwimMsg m → v {
    ( string_free . m from_host )
    ( string_free . m target_host )
    ( vec_free_with [Member] . m gossip \ Member mm → v { ( member_free mm ) } )
}

// ── Wire codec ───────────────────────────────────────────────────────

: | SwimErr {
    SwShort  // truncated datagram
    SwBadType  // unknown message type byte
}

@ swim_err_name SwimErr e → s {
    ^ ?? e { SwShort → `SwShort` SwBadType → `SwBadType` }
}

// u16-length-prefixed string.
@ __sw_put_str ( Vec u ) b s text → v {
    ( bytes_push_u16_be b # u16 ( nurl_str_len text ) )
    ( bytes_extend_str b text )
}

// Read the u16-prefixed string starting at `off`. Returns the String;
// the caller advances `off` by 2 + its byte length.
@ __sw_get_str ( Vec u ) b i off → String {
    : i n ?? ( bytes_read_u16_be b off ) { T x → # i x F → 0 }
    : String s ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        : ?u byte ( vec_get [u] b + + off 2 k )
        ?? byte { T bb → ( string_push_char s # i bb ) F → {} }
        = k + k 1
    }
    ^ s
}

@ __sw_put_member ( Vec u ) b Member m → v {
    ( vec_push [u] b # u ( __state_code . m state ) )
    ( bytes_push_u32_be b # u32 . m incarnation )
    ( __sw_put_str b ( string_data . m host ) )
    ( bytes_push_u16_be b # u16 . m port )
}

@ swim_msg_encode SwimMsg m → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u ( __mtype_code . m mtype ) )
    ( bytes_push_u32_be b # u32 . m seq )
    ( __sw_put_str b ( string_data . m from_host ) )
    ( bytes_push_u16_be b # u16 . m from_port )
    ( __sw_put_str b ( string_data . m target_host ) )
    ( bytes_push_u16_be b # u16 . m target_port )
    : i gn ( vec_len [Member] . m gossip )
    ( bytes_push_u16_be b # u16 gn )
    : ~ i k 0
    ~ < k gn {
        ?? ( vec_get [Member] . m gossip k ) {
            T mm → ( __sw_put_member b mm )
            F → {}
        }
        = k + k 1
    }
    ^ b
}

@ swim_msg_decode ( Vec u ) b → !SwimMsg SwimErr {
    : i len ( vec_len [u] b )
    ? < len 1 { ^ @ !SwimMsg SwimErr { F @ SwimErr { SwShort } } } {}

    : i tc ?? ( vec_get [u] b 0 ) { T x → # i x F → 0 }
    ? | < tc 1 > tc 5 { ^ @ !SwimMsg SwimErr { F @ SwimErr { SwBadType } } } {}
    : SwimMsgType mt ( __mtype_of tc )
    : ~ i off 1

    : i seq ?? ( bytes_read_u32_be b off ) { T x → # i x F → 0 }
    = off + off 4

    : String fh ( __sw_get_str b off )
    = off + + off 2 ( string_len fh )
    : i fp ?? ( bytes_read_u16_be b off ) { T x → # i x F → 0 }
    = off + off 2

    : String th ( __sw_get_str b off )
    = off + + off 2 ( string_len th )
    : i tp ?? ( bytes_read_u16_be b off ) { T x → # i x F → 0 }
    = off + off 2

    : i gn ?? ( bytes_read_u16_be b off ) { T x → # i x F → 0 }
    = off + off 2

    : ( Vec Member ) gossip ( vec_new [Member] )
    : ~ i k 0
    ~ < k gn {
        : i sc ?? ( vec_get [u] b off ) { T x → # i x F → 0 }
        = off + off 1
        : i inc ?? ( bytes_read_u32_be b off ) { T x → # i x F → 0 }
        = off + off 4
        : String mh ( __sw_get_str b off )
        = off + + off 2 ( string_len mh )
        : i mp ?? ( bytes_read_u16_be b off ) { T x → # i x F → 0 }
        = off + off 2
        ( vec_push [Member] gossip
        @ Member { mh mp inc ( __state_of sc ) ( monotonic_ns ) } )
        = k + k 1
    }

    ^ @ !SwimMsg SwimErr { T @ SwimMsg { mt seq fh fp th tp gossip } }
}

// ── Member table + failure detector ──────────────────────────────────
//
// Heap-allocated (pointer-shared) so the protocol loop and any inspector
// observe one mutable view; every op takes the lock. `members` excludes
// self — self is represented by `self_*` and emitted into gossip on demand.

: MemberTable {
    Mutex m
    ( Vec Member ) members
    String self_host
    i self_port
    i self_incarnation
    Rng rng
    i suspect_timeout_ms
}

@ mtable_new s self_host i self_port i suspect_timeout_ms → *MemberTable {
    : *MemberTable t # *MemberTable ( nurl_alloc Z MemberTable )
    = . t m ( mutex_new )
    = . t members ( vec_new [Member] )
    = . t self_host ( string_from self_host )
    = . t self_port self_port
    = . t self_incarnation 0
    = . t rng ( rng_seed ( monotonic_ns ) )
    = . t suspect_timeout_ms suspect_timeout_ms
    ^ t
}

@ mtable_free * MemberTable t → v {
    ( vec_free_with [Member] . t members \ Member mm → v { ( member_free mm ) } )
    ( mutex_free . t m )
    ( string_free . t self_host )
    ( rng_free . t rng )
    ( nurl_free # s t )
}

@ __member_copy Member m → Member {
    ^ @ Member { ( string_from ( string_data . m host ) ) . m port . m incarnation . m state . m last_change_ms }
}

@ __addr_eq s ha i pa s hb i pb → b {
    ^ & == pa pb != 0 ( nurl_str_eq ha hb )
}

// Index of (host,port) in members, or -1. Caller holds the lock.
@ __mtable_find * MemberTable t s host i port → i {
    : i n ( vec_len [Member] . t members )
    : ~ i found - 0 1
    : ~ b done F
    : ~ i k 0
    ~ & ! done < k n {
        ?? ( vec_get [Member] . t members k ) {
            T mm → {
                ? ( __addr_eq ( string_data . mm host ) . mm port host port ) {
                    = found k = done T
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

// Merge one membership update under SWIM precedence. Returns T if the
// local view changed in a way worth re-gossiping (state transition, new
// member, or self-refutation). `up` is BORROWED (caller still owns it).
@ mtable_apply * MemberTable t Member up → b {
    ( mutex_lock . t m )
    : s uh ( string_data . up host )
    : i up_port . up port
    : i ui . up incarnation
    : i us ( __state_code . up state )

    // Update about ourselves → refute any suspicion/death with a higher
    // incarnation so the cluster learns we are alive.
    ? ( __addr_eq uh up_port ( string_data . t self_host ) . t self_port ) {
        : b refute & > us 0 >= ui . t self_incarnation
        ? refute { = . t self_incarnation + ui 1 } {}
        ( mutex_unlock . t m )
        ^ refute
    } {}

    : i idx ( __mtable_find t uh up_port )
    ? < idx 0 {
        ( vec_push [Member] . t members ( __member_copy up ) )
        ( mutex_unlock . t m )
        ^ T
    } {}

    : Member cur ?? ( vec_get [Member] . t members idx ) { T x → x F → up }
    : i ci . cur incarnation
    : i cs ( __state_code . cur state )

    // Precedence: Alive wins on strictly-higher inc; Suspect wins on
    // higher inc or equal-inc-over-Alive; Dead wins on >= inc.
    : b accept ? == us 0 { > ui ci }
    { ? == us 1 { | > ui ci & == ui ci == cs 0 }
        { >= ui ci } }

    ? accept {
        : Member nm @ Member { . cur host up_port ui . up state ( monotonic_ns ) }
        ( vec_set [Member] . t members idx nm )
        ( mutex_unlock . t m )
        ^ != us cs  // re-gossip only on an actual state change
    } {}
    ( mutex_unlock . t m )
    ^ F
}

// Locally mark a member Suspect after a failed probe (keeps its current
// incarnation — a refutation must out-number it). Returns T if changed.
@ mtable_suspect * MemberTable t s host i port → b {
    ( mutex_lock . t m )
    : i idx ( __mtable_find t host port )
    ? < idx 0 { ( mutex_unlock . t m ) ^ F } {}
    : Member cur ?? ( vec_get [Member] . t members idx ) { T x → x F → ( member_new host port 0 @ MemberState { MAlive } ) }
    ? == ( __state_code . cur state ) 0 {
        : Member nm @ Member { . cur host port . cur incarnation @ MemberState { MSuspect } ( monotonic_ns ) }
        ( vec_set [Member] . t members idx nm )
        ( mutex_unlock . t m )
        ^ T
    } {}
    ( mutex_unlock . t m )
    ^ F
}

// Promote Suspect → Dead once the suspicion has aged past the timeout.
// Returns the newly-dead members (owned copies) for gossip dissemination.
@ mtable_sweep * MemberTable t → ( Vec Member ) {
    ( mutex_lock . t m )
    : ( Vec Member ) dead ( vec_new [Member] )
    : i now ( monotonic_ns )
    : i n ( vec_len [Member] . t members )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Member] . t members k ) {
            T cur → {
                ? == ( __state_code . cur state ) 1 {
                    : i age_ms / - now . cur last_change_ms 1000000
                    ? >= age_ms . t suspect_timeout_ms {
                        : Member nm @ Member { . cur host . cur port . cur incarnation @ MemberState { MDead } now }
                        ( vec_set [Member] . t members k nm )
                        ( vec_push [Member] dead ( __member_copy nm ) )
                    } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( mutex_unlock . t m )
    ^ dead
}

// Self as an Alive member snapshot (for gossip + join).
@ mtable_self * MemberTable t → Member {
    ( mutex_lock . t m )
    : Member s @ Member { ( string_from ( string_data . t self_host ) ) . t self_port . t self_incarnation @ MemberState { MAlive } ( monotonic_ns ) }
    ( mutex_unlock . t m )
    ^ s
}

// Pick a random member that is worth probing (Alive or Suspect). None
// when the table has no such member. Returns an owned copy.
@ mtable_pick_probe * MemberTable t → ?Member {
    ( mutex_lock . t m )
    : ( Vec i ) cand ( vec_new [i] )
    : i n ( vec_len [Member] . t members )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Member] . t members k ) {
            T mm → { ? != ( __state_code . mm state ) 2 { ( vec_push [i] cand k ) } {} }
            F → {}
        }
        = k + k 1
    }
    : i cn ( vec_len [i] cand )
    ? == cn 0 {
        ( vec_free [i] cand )
        ( mutex_unlock . t m )
        ^ @ ?Member { F # Member 0 }
    } {}
    : i pick ?? ( vec_get [i] cand ( rng_below . t rng cn ) ) { T x → x F → 0 }
    ( vec_free [i] cand )
    : ?Member out ?? ( vec_get [Member] . t members pick ) {
        T mm → @ ?Member { T ( __member_copy mm ) }
        F → @ ?Member { F # Member 0 }
    }
    ( mutex_unlock . t m )
    ^ out
}

// Up to `k` random members other than (host,port) — the indirect-probe
// relays. Owned copies.
@ mtable_pick_relays * MemberTable t i k s ex_host i ex_port → ( Vec Member ) {
    ( mutex_lock . t m )
    : ( Vec i ) cand ( vec_new [i] )
    : i n ( vec_len [Member] . t members )
    : ~ i j 0
    ~ < j n {
        ?? ( vec_get [Member] . t members j ) {
            T mm → {
                ? & != ( __state_code . mm state ) 2
                ! ( __addr_eq ( string_data . mm host ) . mm port ex_host ex_port ) {
                    ( vec_push [i] cand j )
                } {}
            }
            F → {}
        }
        = j + j 1
    }
    : ( Vec Member ) out ( vec_new [Member] )
    : i cn ( vec_len [i] cand )
    : ~ i taken 0
    ~ & < taken k > ( vec_len [i] cand ) 0 {
        : i ci ( rng_below . t rng ( vec_len [i] cand ) )
        : i mi ?? ( vec_get [i] cand ci ) { T x → x F → 0 }
        ?? ( vec_get [Member] . t members mi ) {
            T mm → ( vec_push [Member] out ( __member_copy mm ) )
            F → {}
        }
        ( vec_remove [i] cand ci )  // sample without replacement
        = taken + taken 1
    }
    ( vec_free [i] cand )
    ( mutex_unlock . t m )
    ^ out
}

// Gossip sample: self (Alive) plus up to `max` random members. Owned.
@ mtable_gossip * MemberTable t i max → ( Vec Member ) {
    : ( Vec Member ) g ( vec_new [Member] )
    ( vec_push [Member] g ( mtable_self t ) )
    ( mutex_lock . t m )
    : i n ( vec_len [Member] . t members )
    : ~ i taken 0
    : ~ i k 0
    ~ & < k n < taken max {
        ?? ( vec_get [Member] . t members k ) {
            T mm → ( vec_push [Member] g ( __member_copy mm ) )
            F → {}
        }
        = taken + taken 1
        = k + k 1
    }
    ( mutex_unlock . t m )
    ^ g
}

@ mtable_count * MemberTable t → i {
    ( mutex_lock . t m )
    : i n ( vec_len [Member] . t members )
    ( mutex_unlock . t m )
    ^ n
}

// All members (excluding self) as owned copies — for inspection / UIs.
@ mtable_snapshot * MemberTable t → ( Vec Member ) {
    ( mutex_lock . t m )
    : ( Vec Member ) out ( vec_new [Member] )
    : i n ( vec_len [Member] . t members )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Member] . t members k ) {
            T mm → ( vec_push [Member] out ( __member_copy mm ) )
            F → {}
        }
        = k + k 1
    }
    ( mutex_unlock . t m )
    ^ out
}

// State of (host,port) as a code (0/1/2), or -1 if unknown. For tests.
@ mtable_state_of * MemberTable t s host i port → i {
    ( mutex_lock . t m )
    : i idx ( __mtable_find t host port )
    : i st ? < idx 0 - 0 1 ?? ( vec_get [Member] . t members idx ) { T mm → ( __state_code . mm state ) F → - 0 1 }
    ( mutex_unlock . t m )
    ^ st
}

// ── Protocol: UDP I/O loop ───────────────────────────────────────────
//
// Direct-probe SWIM: each protocol period the failure detector PINGs one
// random member and waits for an ACK; a missed ACK marks the member
// Suspect, and the sweep promotes a stale Suspect to Dead. Membership
// changes ride along as gossip on every PING/ACK. (Indirect PING-REQ to
// suppress single-path false positives is wired into the message format
// but driven by a follow-up.)
//
// Two fibers: a receiver (answer PINGs, record ACKs, merge gossip) and
// the failure detector. Heap-allocated so both fibers share one node.

// A pending indirect probe this node is relaying on a peer's behalf: it
// PINGed `target` with `probe_seq`; when that ACK arrives it forwards an
// ACK carrying `orig_seq` back to `req_host:req_port`. `created_ms` ages
// the entry out if the target never answers.
: FwdEntry {
    i probe_seq
    String req_host
    i req_port
    i orig_seq
    i created_ms
}

: SwimNode {
    * MemberTable table
    UdpSocket sock
    String host
    i port
    Mutex ack_m
    ( Vec i ) acked  // ACK seqs seen since the last sweep
    i seq_ctr
    i period_ms
    i ping_timeout_ms
    i indirect_k  // # of relays for an indirect (PING-REQ) probe
    Mutex fwd_m
    ( Vec FwdEntry ) fwd  // indirect probes we are relaying
    i running
}

@ swim_node_new s host i port i period_ms i ping_timeout_ms i suspect_timeout_ms → !*SwimNode NetErr {
    : !UdpSocket NetErr sr ( udp_bind host port )
    ^ ?? sr {
        T sock → {
            ( udp_set_timeout sock 500 )
            : *SwimNode n # *SwimNode ( nurl_alloc Z SwimNode )
            = . n table ( mtable_new host port suspect_timeout_ms )
            = . n sock sock
            = . n host ( string_from host )
            = . n port port
            = . n ack_m ( mutex_new )
            = . n acked ( vec_new [i] )
            = . n seq_ctr 0
            = . n period_ms period_ms
            = . n ping_timeout_ms ping_timeout_ms
            = . n indirect_k 2
            = . n fwd_m ( mutex_new )
            = . n fwd ( vec_new [FwdEntry] )
            = . n running 1
            @ !*SwimNode NetErr { T n }
        }
        F e → @ !*SwimNode NetErr { F # NetErr e }
    }
}

@ __node_table * SwimNode n → *MemberTable { ^ . n table }

@ swim_table * SwimNode n → *MemberTable { ^ ( __node_table n ) }

@ swim_node_free * SwimNode n → v {
    ( mtable_free ( __node_table n ) )
    ( udp_close . n sock )
    ( mutex_free . n ack_m )
    ( vec_free [i] . n acked )
    ( vec_free_with [FwdEntry] . n fwd \ FwdEntry e → v { ( string_free . e req_host ) } )
    ( mutex_free . n fwd_m )
    ( string_free . n host )
    ( nurl_free # s n )
}

@ __node_send * SwimNode n s host i port SwimMsg m → v {
    : ( Vec u ) bytes ( swim_msg_encode m )
    : !i NetErr r ( udp_send_to . n sock bytes host port )
    ?? r { T _ → {} F _ → {} }
    ( vec_free [u] bytes )
}

// Build a message of `ty` carrying a fresh gossip sample.
@ __mk_msg * SwimNode n SwimMsgType ty i seq s th i tp → SwimMsg {
    : ( Vec Member ) g ( mtable_gossip ( __node_table n ) 6 )
    ^ @ SwimMsg { ty seq ( string_from ( string_data . n host ) ) . n port ( string_from th ) tp g }
}

@ __apply_gossip * SwimNode n ( Vec Member ) g → v {
    : i gn ( vec_len [Member] g )
    : ~ i k 0
    ~ < k gn {
        ?? ( vec_get [Member] g k ) {
            T mm → { : b _c ( mtable_apply ( __node_table n ) mm ) }
            F → {}
        }
        = k + k 1
    }
}

@ __handle * SwimNode n SwimMsg m → v {
    ( __apply_gossip n . m gossip )
    : i ty ( __mtype_code . m mtype )
    ? == ty 1 {  // PING → ACK (echo seq)
        : SwimMsg ack ( __mk_msg n @ SwimMsgType { MtAck } . m seq `` 0 )
        ( __node_send n ( string_data . m from_host ) . m from_port ack )
        ( swim_msg_free ack )
    } {}
    ? == ty 2 {  // ACK → record seq
        ( mutex_lock . n ack_m )
        ( vec_push [i] . n acked . m seq )
        ( mutex_unlock . n ack_m )
        // If this ACK completes an indirect probe we are relaying, forward
        // it to the original requester.
        ( __try_forward_ack n . m seq )
    } {}
    ? == ty 3 {  // PING-REQ → probe target for peer
        = . n seq_ctr + . n seq_ctr 1
        : i probe_seq . n seq_ctr
        ( mutex_lock . n fwd_m )
        ( vec_push [FwdEntry] . n fwd @ FwdEntry { probe_seq
            ( string_from ( string_data . m from_host ) ) . m from_port . m seq
            / ( monotonic_ns ) 1000000 } )
        ( mutex_unlock . n fwd_m )
        : SwimMsg ping ( __mk_msg n @ SwimMsgType { MtPing } probe_seq `` 0 )
        ( __node_send n ( string_data . m target_host ) . m target_port ping )
        ( swim_msg_free ping )
    } {}
    ? == ty 4 {  // JOIN → reply with our view
        : SwimMsg ja ( __mk_msg n @ SwimMsgType { MtJoinAck } . m seq `` 0 )
        ( __node_send n ( string_data . m from_host ) . m from_port ja )
        ( swim_msg_free ja )
    } {}
    // MtJoinAck (5): gossip already merged.
}

// A target's ACK to one of our relayed probes (`probe_seq`) → forward an
// ACK carrying the requester's original seq back to them, and drop the
// pending entry. No-op when `seq` matches no pending relay.
@ __try_forward_ack * SwimNode n i seq → v {
    ( mutex_lock . n fwd_m )
    : i nn ( vec_len [FwdEntry] . n fwd )
    : ~ i idx - 0 1
    : ~ b fdone F
    : ~ i k 0
    ~ & ! fdone < k nn {
        ?? ( vec_get [FwdEntry] . n fwd k ) {
            T e → { ? == . e probe_seq seq { = idx k = fdone T } {} }
            F → {}
        }
        = k + k 1
    }
    ? < idx 0 { ( mutex_unlock . n fwd_m ) } {
        ?? ( vec_get [FwdEntry] . n fwd idx ) {
            T e → {
                : String rh ( string_from ( string_data . e req_host ) )
                : i rp . e req_port
                : i oseq . e orig_seq
                ( string_free . e req_host )
                ( vec_remove [FwdEntry] . n fwd idx )
                ( mutex_unlock . n fwd_m )
                : SwimMsg ack ( __mk_msg n @ SwimMsgType { MtAck } oseq `` 0 )
                ( __node_send n ( string_data rh ) rp ack )
                ( swim_msg_free ack )
                ( string_free rh )
            }
            F → ( mutex_unlock . n fwd_m )
        }
    }
}

// Drop relayed probes older than 2× the ping timeout (the target never
// answered) so the pending list can't grow without bound.
@ __prune_fwd * SwimNode n → v {
    ( mutex_lock . n fwd_m )
    : i now / ( monotonic_ns ) 1000000
    : i cutoff * . n ping_timeout_ms 2
    : ~ i k 0
    ~ < k ( vec_len [FwdEntry] . n fwd ) {
        : ~ b drop F
        ?? ( vec_get [FwdEntry] . n fwd k ) {
            T e → { ? > - now . e created_ms cutoff { = drop T ( string_free . e req_host ) } {} }
            F → {}
        }
        ? drop { ( vec_remove [FwdEntry] . n fwd k ) } { = k + k 1 }
    }
    ( mutex_unlock . n fwd_m )
}

@ __recv_loop * SwimNode n → v {
    ~ != 0 . n running {
        : !UdpPacket NetErr r ( udp_recv_from . n sock 2048 )
        ?? r {
            T pkt → {
                : !SwimMsg SwimErr d ( swim_msg_decode . pkt data )
                ?? d {
                    T m → { ( __handle n m ) ( swim_msg_free m ) }
                    F _ → {}
                }
                ( udp_packet_free pkt )
            }
            F _ → {}  // timeout → re-check running
        }
    }
}

@ __got_ack * SwimNode n i seq → b {
    ( mutex_lock . n ack_m )
    : i nn ( vec_len [i] . n acked )
    : ~ b found F
    : ~ i k 0
    ~ & ! found < k nn {
        ?? ( vec_get [i] . n acked k ) { T x → ?== x seq { = found T } {} F → {} }
        = k + k 1
    }
    ( mutex_unlock . n ack_m )
    ^ found
}

// Ask up to `indirect_k` random members to PING the target on our behalf.
// Returns T if any relay reports back an ACK within the ping timeout (the
// target is alive via some path). F when no relay answers — or when there
// are no relays to ask.
@ __indirect_probe * SwimNode n String thost i tport → b {
    = . n seq_ctr + . n seq_ctr 1
    : i iseq . n seq_ctr
    : ( Vec Member ) relays ( mtable_pick_relays ( __node_table n ) . n indirect_k ( string_data thost ) tport )
    : i rn ( vec_len [Member] relays )
    : ~ i ri 0
    ~ < ri rn {
        ?? ( vec_get [Member] relays ri ) {
            T rly → {
                : SwimMsg pr ( __mk_msg n @ SwimMsgType { MtPingReq } iseq ( string_data thost ) tport )
                ( __node_send n ( string_data . rly host ) . rly port pr )
                ( swim_msg_free pr )
            }
            F → {}
        }
        = ri + ri 1
    }
    ( vec_free_with [Member] relays \ Member d → v { ( member_free d ) } )
    ? == rn 0 { ^ F } {}
    : ~ b iok F
    : ~ i iwaited 0
    ~ & ! iok < iwaited . n ping_timeout_ms {
        ( sleep_ms 10 )
        = iwaited + iwaited 10
        ? ( __got_ack n iseq ) { = iok T } {}
    }
    ^ iok
}

@ __fd_loop * SwimNode n → v {
    ~ != 0 . n running {
        ( sleep_ms . n period_ms )
        : ?Member tgt ( mtable_pick_probe ( __node_table n ) )
        ?? tgt {
            T mm → {
                = . n seq_ctr + . n seq_ctr 1
                : i seq . n seq_ctr
                : SwimMsg ping ( __mk_msg n @ SwimMsgType { MtPing } seq `` 0 )
                ( __node_send n ( string_data . mm host ) . mm port ping )
                ( swim_msg_free ping )
                : ~ b ok F
                : ~ i waited 0
                ~ & ! ok < waited . n ping_timeout_ms {
                    ( sleep_ms 10 )
                    = waited + waited 10
                    ? ( __got_ack n seq ) { = ok T } {}
                }
                ? ! ok {
                    // Direct PING timed out — don't suspect yet. Ask k
                    // random members to probe the target indirectly; a
                    // single lossy path between us and the target then
                    // can't cause a false positive.
                    : b iok ( __indirect_probe n . mm host . mm port )
                    ? ! iok {
                        : b _s ( mtable_suspect ( __node_table n ) ( string_data . mm host ) . mm port )
                    } {}
                } {}
                ( member_free mm )
            }
            F → {}
        }
        : ( Vec Member ) dead ( mtable_sweep ( __node_table n ) )
        ( vec_free_with [Member] dead \ Member d → v { ( member_free d ) } )
        ( __prune_fwd n )
        ( mutex_lock . n ack_m )
        ( vec_clear [i] . n acked )
        ( mutex_unlock . n ack_m )
    }
}

// Announce ourselves to a seed node (it learns us via the JOIN's gossip
// and replies with its own membership).
@ swim_join * SwimNode n s seed_host i seed_port → v {
    : SwimMsg j ( __mk_msg n @ SwimMsgType { MtJoin } 0 `` 0 )
    ( __node_send n seed_host seed_port j )
    ( swim_msg_free j )
}

// Spawn the receiver + failure-detector fibers. Requires runtime_init /
// runtime_run by the caller.
@ swim_run * SwimNode n → v {
    ( spawn \ → v { ( __recv_loop n ) } )
    ( spawn \ → v { ( __fd_loop n ) } )
}

@ swim_stop * SwimNode n → v { = . n running 0 }
