// stdlib/net/failuredetector.nu — SWIM failure-detector control loop over
// net/membership (§7.4 Phase 5). This is the PROBE STATE MACHINE that turns
// the membership table into a live detector:
//
//   every `period`  → probe a member (direct PING);
//   no ack by `direct_timeout` → escalate to an indirect PING-REQ via k
//     relays (over net/transport this maps onto the relay alternate path —
//     if A can't reach B directly, a relay can);
//   no ack at all by `total_timeout` → suspect the member (Lifeguard
//     confirmation- + local-health-scaled suspicion then sweeps it to dead);
//   a direct ack (even a LATE one, e.g. after a wifi↔cellular roam) → the
//     member stays / returns alive and local health improves.
//
// The control logic is PURE and time-injected: fd_tick(now) returns the next
// FdAction (none / ping / ping-req) and mutates only the detector's own probe
// bookkeeping + the membership table; fd_on_ack / fd_on_gossip feed events
// in. The actual transport I/O (perform the action, read replies) is a thin
// adapter the caller writes — so the whole "is the cluster stable across a
// forced network change?" question is a deterministic scenario test here, not
// a live-socket guess.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/std/lifeguard.nu`

@ fd_none    → i { ^ 0 }
@ fd_do_ping → i { ^ 1 }
@ fd_do_preq → i { ^ 2 }

@ __fd_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

// What the caller should put on the wire this tick.
: FdAction {
    i kind            // 0 none, 1 ping, 2 ping-req
    ( Vec u ) target  // pubkey to probe (owned copy; empty for none)
    i seq
    ( Vec s ) relays  // ping-req: borrowed *PkMember relays (table-owned)
}
@ fd_action_free FdAction a → v { ( vec_free [u] . a target ) ( vec_free [s] . a relays ) }
@ __fd_none → FdAction { ^ @ FdAction { ( fd_none ) ( vec_new [u] ) 0 ( vec_new [s] ) } }

: FdState {
    s table              // *PkMemberTable
    i period_ns
    i direct_timeout_ns  // direct-ack window before escalating to ping-req
    i total_timeout_ns   // total window before suspecting
    i k_indirect         // relays for a ping-req
    i next_seq
    i probing            // 1 = a probe is in flight
    ( Vec u ) probe_target
    i probe_seq
    i probe_start_ns
    i probe_indirect     // 1 = ping-req already escalated for this probe
    i last_probe_ns
}

@ fd_new s table i period_ns i direct_timeout_ns i total_timeout_ns i k_indirect → *FdState {
    : *FdState fd # *FdState ( nurl_alloc Z FdState )
    = . fd table table
    = . fd period_ns period_ns
    = . fd direct_timeout_ns direct_timeout_ns
    = . fd total_timeout_ns total_timeout_ns
    = . fd k_indirect k_indirect
    = . fd next_seq 1
    = . fd probing 0
    = . fd probe_target ( vec_new [u] )
    = . fd probe_seq 0
    = . fd probe_start_ns 0
    = . fd probe_indirect 0
    = . fd last_probe_ns - 0 period_ns   // eligible to probe immediately
    ^ fd
}
@ fd_free *FdState fd → v { ( vec_free [u] . fd probe_target ) ( nurl_free # s fd ) }
@ fd_probing *FdState fd → i { ^ . fd probing }

// Advance the detector. Returns at most one action; the caller performs it.
@ fd_tick *FdState fd i now → FdAction {
    : *PkMemberTable t # *PkMemberTable . fd table
    ? == . fd probing 1 {
        : i elapsed - now . fd probe_start_ns
        ? >= elapsed . fd total_timeout_ns {
            ( pktable_suspect t . fd probe_target now )
            ( pktable_on_probe_fail t )
            = . fd probing 0
            = . fd last_probe_ns now
            ^ ( __fd_none )
        } {}
        ? & == . fd probe_indirect 0 >= elapsed . fd direct_timeout_ns {
            = . fd probe_indirect 1
            : ( Vec s ) relays ( pktable_pick_relays t . fd k_indirect . fd probe_target )
            ^ @ FdAction { ( fd_do_preq ) ( __fd_cpy . fd probe_target ) . fd probe_seq relays }
        } {}
        ^ ( __fd_none )
    } {}
    ? >= - now . fd last_probe_ns . fd period_ns {
        : ?( Vec u ) tgt ( pktable_pick_probe t )
        : FdAction out ?? tgt {
            T pk → {
                = . fd probing 1
                = . fd probe_indirect 0
                = . fd probe_seq . fd next_seq
                = . fd next_seq + . fd next_seq 1
                = . fd probe_start_ns now
                = . fd last_probe_ns now
                ( vec_free [u] . fd probe_target )
                = . fd probe_target ( __fd_cpy pk )
                : FdAction a @ FdAction { ( fd_do_ping ) ( __fd_cpy pk ) . fd probe_seq ( vec_new [s] ) }
                ( vec_free [u] pk )
                a
            }
            F → ( __fd_none )
        }
        ^ out
    } {}
    ^ ( __fd_none )
}

// A direct ack for the in-flight probe arrived (possibly late, after a roam):
// the member is alive, local health improves, the probe completes.
@ fd_on_ack *FdState fd i seq i now → b {
    ? & == . fd probing 1 == seq . fd probe_seq {
        : *PkMemberTable t # *PkMemberTable . fd table
        ( pktable_observe_alive t . fd probe_target now )
        ( pktable_on_probe_ok t )
        = . fd probing 0
        ^ T
    } {}
    ^ F
}

// Merge a peer's piggybacked gossip into the table.
@ fd_on_gossip *FdState fd PkMsg m i now → v {
    : *PkMemberTable t # *PkMemberTable . fd table
    ( pktable_apply_gossip t m now )
}

// Promote expired suspicions to dead (caller runs each tick); returns the
// newly-dead as borrowed *PkMember (free the container with __pk_dead_free).
@ fd_sweep *FdState fd i now → ( Vec s ) {
    : *PkMemberTable t # *PkMemberTable . fd table
    ^ ( pktable_sweep t now )
}
