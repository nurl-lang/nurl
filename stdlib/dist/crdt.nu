// stdlib/dist/crdt.nu — conflict-free replicated data types (§7.4 Phase 6).
// State-based CRDTs whose `merge` is commutative, associative and idempotent,
// so replicas converge by exchanging state over gossip — eventual
// consistency with NO coordination and NO consensus (no Raft/Paxos), which is
// what a churning mobile mesh needs. (Delta-state — gossiping only recent
// changes instead of full state — is an optimization over the same merge.)
//
//   PNCounter    — increment/decrement counter (per-replica G-counters).
//   LwwReg       — last-writer-wins register (value + timestamp + replica).
//   OrSet        — observed-remove set: concurrent add wins over remove.
//
// Replicas are identified by a GLOBALLY STABLE integer id derived from the node
// pubkey (dist/identity.nu's identity_stable_id) — NOT by local arrival order.
// This matters: the merge aligns replica slots BY ID, so every node must name a
// replica the same way without coordination, or distinct replicas collide into
// one slot and the value silently corrupts. Merge is the gossip primitive: on
// receiving a peer's CRDT, merge it into the local one.
//
// PNCounter and OrSet are handles: every copy is the same replica, and its
// last owner releases it (pncounter_free / orset_free are early releases,
// optional). LwwReg is a plain value.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

// ════════════════════════════════════════════════════════════════
// PNCounter — per-replica increments and decrements; value = Σinc − Σdec.
// Stored SPARSELY as (replica-id, amount) pairs and merged by matching id
// (each replica's per-id total is a grow-only counter → merge = max per id).
// Keying by id rather than vector position is what makes convergence correct
// when replicas are discovered in different orders on different nodes.
// ════════════════════════════════════════════════════════════════

: PNCounterImpl {
    ( Vec i ) inc_id  // replica ids that have incremented
    ( Vec i ) inc_amt  // inc_amt[k] = total increments by replica inc_id[k]
    ( Vec i ) dec_id
    ( Vec i ) dec_amt
}

// A PNCounter is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: PNCounter { s ctl }

@ PNCounter_share PNCounter h → PNCounter { ^ @ PNCounter { # s ( rcbox_share # i . h ctl ) } }

@ PNCounter_drop sink PNCounter h → v {
    ( mem_forget h )
    ( rcbox_release [PNCounterImpl] # i . h ctl )
}

@ __PNCounter_ptr PNCounter h → *PNCounterImpl { ^ ( rcbox_ptr [PNCounterImpl] # i . h ctl ) }

@ pncounter_new → PNCounter {
    : i c__box ( rcbox_zero [PNCounterImpl] )
    : *PNCounterImpl c ( rcbox_ptr [PNCounterImpl] c__box )
    = . c inc_id ( vec_new [i] )
    = . c inc_amt ( vec_new [i] )
    = . c dec_id ( vec_new [i] )
    = . c dec_amt ( vec_new [i] )
    ^ @ PNCounter { # s c__box }
}

// Let go of `c` now rather than at the end of its owner's scope.
@ pncounter_free sink PNCounter c → v {}

@ __pn_at ( Vec i ) v i idx → i { ^ ?? ( vec_get [i] v idx ) { T x → x F → 0 } }

@ __pn_sum ( Vec i ) v → i {
    : i n ( vec_len [i] v ) : ~ i s 0 : ~ i k 0
    ~ < k n { = s + s ( __pn_at v k ) = k + k 1 }
    ^ s
}
// index of replica `id` in `ids`, or -1
@ __pn_idx ( Vec i ) ids i id → i {
    : i n ( vec_len [i] ids ) : ~ i found -1 : ~ i k 0
    ~ & == found -1 < k n { ? == ?? ( vec_get [i] ids k ) { T x → x F → 0 } id { = found k } {} = k + k 1 }
    ^ found
}
// add `amt` to replica `id`'s grow-only slot (append if first seen)
@ __pn_bump ( Vec i ) ids ( Vec i ) amts i id i amt → v {
    : i j ( __pn_idx ids id )
    ? >= j 0 { ( vec_set [i] amts j + ( __pn_at amts j ) amt ) } { ( vec_push [i] ids id ) ( vec_push [i] amts amt ) }
}

@ pncounter_inc PNCounter c__h i replica i amt → v {
    : *PNCounterImpl c ( __PNCounter_ptr c__h )
    ( __pn_bump . c inc_id . c inc_amt replica amt )
}

@ pncounter_dec PNCounter c__h i replica i amt → v {
    : *PNCounterImpl c ( __PNCounter_ptr c__h )
    ( __pn_bump . c dec_id . c dec_amt replica amt )
}

@ pncounter_value PNCounter c__h → i {
    : *PNCounterImpl c ( __PNCounter_ptr c__h )
    ^ - ( __pn_sum . c inc_amt ) ( __pn_sum . c dec_amt )
}

// merge src (ids,amts) into dst, taking the max per replica id (insert if new)
@ __pn_max_into ( Vec i ) dids ( Vec i ) damts ( Vec i ) sids ( Vec i ) samts → v {
    : i ns ( vec_len [i] sids ) : ~ i k 0
    ~ < k ns {
        : i id ?? ( vec_get [i] sids k ) { T x → x F → 0 }
        : i sv ( __pn_at samts k )
        : i j ( __pn_idx dids id )
        ? >= j 0 { ? > sv ( __pn_at damts j ) { ( vec_set [i] damts j sv ) } {} } { ( vec_push [i] dids id ) ( vec_push [i] damts sv ) }
        = k + k 1
    }
}
// The sparse columns, lent — what dist/replicator.nu's codec reads and
// fills: replica ids and their grow-only totals, increments and decrements.
@ pncounter_inc_ids PNCounter c__h → ( Vec i ) {
    : *PNCounterImpl c ( __PNCounter_ptr c__h )
    ^ . c inc_id
}

@ pncounter_inc_amts PNCounter c__h → ( Vec i ) {
    : *PNCounterImpl c ( __PNCounter_ptr c__h )
    ^ . c inc_amt
}

@ pncounter_dec_ids PNCounter c__h → ( Vec i ) {
    : *PNCounterImpl c ( __PNCounter_ptr c__h )
    ^ . c dec_id
}

@ pncounter_dec_amts PNCounter c__h → ( Vec i ) {
    : *PNCounterImpl c ( __PNCounter_ptr c__h )
    ^ . c dec_amt
}

// Merge a peer's counter into this one (idempotent, commutative).
@ pncounter_merge PNCounter a__h PNCounter b__h → v {
    : *PNCounterImpl a ( __PNCounter_ptr a__h )
    : *PNCounterImpl b ( __PNCounter_ptr b__h )
    ( __pn_max_into . a inc_id . a inc_amt . b inc_id . b inc_amt )
    ( __pn_max_into . a dec_id . a dec_amt . b dec_id . b dec_amt )
}

// ════════════════════════════════════════════════════════════════
// LwwReg — last-writer-wins register. Higher timestamp wins; ties broken
// deterministically by replica id so all replicas pick the same winner.
// ════════════════════════════════════════════════════════════════

: LwwReg {
    i value
    i ts
    i replica
}

@ lww_new → LwwReg { ^ @ LwwReg { 0 0 - 0 1 } }  // ts 0, replica -1 = "unset"
@ lww_set LwwReg r i value i ts i replica → LwwReg { ^ @ LwwReg { value ts replica } }

@ lww_value LwwReg r → i { ^ . r value }

@ lww_ts LwwReg r → i { ^ . r ts }

@ lww_merge LwwReg a LwwReg b → LwwReg {
    ? > . a ts . b ts { ^ a } {}
    ? > . b ts . a ts { ^ b } {}
    ? >= . a replica . b replica { ^ a } {}
    ^ b
}

// ════════════════════════════════════════════════════════════════
// OrSet — observed-remove set. Each add carries a unique tag (replica,seq);
// remove tombstones the tags it has OBSERVED. An element is present iff it has
// an add-tag with no tombstone → a concurrent add WINS over a remove.
// merge = union of adds ∪ union of tombs. Elements are integers (caller maps).
// ════════════════════════════════════════════════════════════════

: OrTag {
    i elem
    i replica
    i seq
}

: OrSetImpl {
    ( Vec s ) adds  // *OrTag
    ( Vec s ) tombs  // *OrTag
    i next_seq  // this replica's local tag counter
}

// An OrSet is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: OrSet { s ctl }

@ OrSet_share OrSet h → OrSet { ^ @ OrSet { # s ( rcbox_share # i . h ctl ) } }

@ OrSet_drop sink OrSet h → v {
    ( mem_forget h )
    ( rcbox_release [OrSetImpl] # i . h ctl )
}

@ __OrSet_ptr OrSet h → *OrSetImpl { ^ ( rcbox_ptr [OrSetImpl] # i . h ctl ) }

@ orset_new → OrSet {
    : i s__box ( rcbox_zero [OrSetImpl] )
    : *OrSetImpl s ( rcbox_ptr [OrSetImpl] s__box )
    = . s adds ( vec_new [s] )
    = . s tombs ( vec_new [s] )
    = . s next_seq 0
    ^ @ OrSet { # s s__box }
}

@ __orset_free_tags ( Vec s ) v → v {
    : i n ( vec_len [s] v ) : ~ i k 0
    ~ < k n { : s pp ?? ( vec_get [s] v k ) { T x → x F → # s 0 } ? != # i pp 0 { ( nurl_free pp ) } {} = k + k 1 }
}

// The tags are raw blocks the two Vecs only point at: releasing them is
// the set's own drop, run by its last owner (the Vecs go after it).
% Drop OrSetImpl {
    @ drop OrSetImpl x → v {
        ( __orset_free_tags . x adds )
        ( __orset_free_tags . x tombs )
    }
}

// Let go of `s` now rather than at the end of its owner's scope.
@ orset_free sink OrSet s → v {}

@ __tag_in ( Vec s ) v i elem i replica i seq → b {
    : i n ( vec_len [s] v ) : ~ b found F : ~ i k 0
    ~ & ! found < k n {
        : s pp ?? ( vec_get [s] v k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *OrTag t # *OrTag pp
            ? & & == . t elem elem == . t replica replica == . t seq seq { = found T } {}
        } {}
        = k + k 1
    }
    ^ found
}

@ __tag_push ( Vec s ) v i elem i replica i seq → v {
    : *OrTag t # *OrTag ( nurl_alloc Z OrTag )
    = . t elem elem = . t replica replica = . t seq seq
    ( vec_push [s] v # s t )
}

// Add an element under this replica's id (gets a fresh unique tag).
@ orset_add OrSet s__h i replica i elem → v {
    : *OrSetImpl s ( __OrSet_ptr s__h )
    ( __tag_push . s adds elem replica . s next_seq )
    = . s next_seq + . s next_seq 1
}

// Remove an element: tombstone every currently-observed add-tag for it.
@ orset_remove OrSet s__h i elem → v {
    : *OrSetImpl s ( __OrSet_ptr s__h )
    : i n ( vec_len [s] . s adds ) : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . s adds k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *OrTag t # *OrTag pp
            ? & == . t elem elem ! ( __tag_in . s tombs . t elem . t replica . t seq ) {
                ( __tag_push . s tombs . t elem . t replica . t seq )
            } {}
        } {}
        = k + k 1
    }
}

// Present iff some add-tag for the element is not tombstoned.
@ orset_contains OrSet s__h i elem → b {
    : *OrSetImpl s ( __OrSet_ptr s__h )
    : i n ( vec_len [s] . s adds ) : ~ b found F : ~ i k 0
    ~ & ! found < k n {
        : s pp ?? ( vec_get [s] . s adds k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *OrTag t # *OrTag pp
            ? & == . t elem elem ! ( __tag_in . s tombs . t elem . t replica . t seq ) { = found T } {}
        } {}
        = k + k 1
    }
    ^ found
}

@ __merge_tags ( Vec s ) dst ( Vec s ) src → v {
    : i n ( vec_len [s] src ) : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] src k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *OrTag t # *OrTag pp
            ? ! ( __tag_in dst . t elem . t replica . t seq ) { ( __tag_push dst . t elem . t replica . t seq ) } {}
        } {}
        = k + k 1
    }
}
// The add-tags and tombstones (*OrTag each), lent — what
// dist/replicator.nu's codec reads and fills. The set owns the tags.
@ orset_adds OrSet s__h → ( Vec s ) {
    : *OrSetImpl s ( __OrSet_ptr s__h )
    ^ . s adds
}

@ orset_tombs OrSet s__h → ( Vec s ) {
    : *OrSetImpl s ( __OrSet_ptr s__h )
    ^ . s tombs
}

// Merge a peer's set (union adds, union tombs) — idempotent, commutative.
@ orset_merge OrSet a__h OrSet b__h → v {
    : *OrSetImpl a ( __OrSet_ptr a__h )
    : *OrSetImpl b ( __OrSet_ptr b__h )
    ( __merge_tags . a adds . b adds )
    ( __merge_tags . a tombs . b tombs )
}
