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
// Replicas are identified by a small integer id (the caller maps node pubkey
// → replica id). Merge is the gossip primitive: on receiving a peer's CRDT,
// merge it into the local one.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ════════════════════════════════════════════════════════════════
// PNCounter — per-replica increments and decrements; value = Σinc − Σdec.
// merge = element-wise max of both vectors (a grow-only counter each).
// ════════════════════════════════════════════════════════════════

: PNCounter {
    ( Vec i ) inc   // inc[r] = total increments by replica r
    ( Vec i ) dec   // dec[r] = total decrements by replica r
}

@ pncounter_new → *PNCounter {
    : *PNCounter c # *PNCounter ( nurl_alloc Z PNCounter )
    = . c inc ( vec_new [i] )
    = . c dec ( vec_new [i] )
    ^ c
}
@ pncounter_free *PNCounter c → v { ( vec_free [i] . c inc ) ( vec_free [i] . c dec ) ( nurl_free # s c ) }

@ __pn_ensure ( Vec i ) v i idx → v { ~ <= ( vec_len [i] v ) idx { ( vec_push [i] v 0 ) } }
@ __pn_at ( Vec i ) v i idx → i { ^ ?? ( vec_get [i] v idx ) { T x → x F → 0 } }
@ __pn_sum ( Vec i ) v → i {
    : i n ( vec_len [i] v ) : ~ i s 0 : ~ i k 0
    ~ < k n { = s + s ( __pn_at v k ) = k + k 1 }
    ^ s
}

@ pncounter_inc *PNCounter c i replica i amt → v {
    ( __pn_ensure . c inc replica )
    ( vec_set [i] . c inc replica + ( __pn_at . c inc replica ) amt )
}
@ pncounter_dec *PNCounter c i replica i amt → v {
    ( __pn_ensure . c dec replica )
    ( vec_set [i] . c dec replica + ( __pn_at . c dec replica ) amt )
}
@ pncounter_value *PNCounter c → i { ^ - ( __pn_sum . c inc ) ( __pn_sum . c dec ) }

@ __pn_max_into ( Vec i ) dst ( Vec i ) src → v {
    : i ns ( vec_len [i] src )
    ~ < ( vec_len [i] dst ) ns { ( vec_push [i] dst 0 ) }
    : ~ i k 0
    ~ < k ns {
        : i sv ( __pn_at src k )
        ? > sv ( __pn_at dst k ) { ( vec_set [i] dst k sv ) } {}
        = k + k 1
    }
}
// Merge a peer's counter into this one (idempotent, commutative).
@ pncounter_merge *PNCounter a *PNCounter b → v {
    ( __pn_max_into . a inc . b inc )
    ( __pn_max_into . a dec . b dec )
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

@ lww_new → LwwReg { ^ @ LwwReg { 0 0 - 0 1 } }   // ts 0, replica -1 = "unset"
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

: OrSet {
    ( Vec s ) adds    // *OrTag
    ( Vec s ) tombs   // *OrTag
    i next_seq        // this replica's local tag counter
}

@ orset_new → *OrSet {
    : *OrSet s # *OrSet ( nurl_alloc Z OrSet )
    = . s adds ( vec_new [s] )
    = . s tombs ( vec_new [s] )
    = . s next_seq 0
    ^ s
}
@ __orset_free_vec ( Vec s ) v → v {
    : i n ( vec_len [s] v ) : ~ i k 0
    ~ < k n { : s pp ?? ( vec_get [s] v k ) { T x → x F → # s 0 } ? != # i pp 0 { ( nurl_free pp ) } {} = k + k 1 }
    ( vec_free [s] v )
}
@ orset_free *OrSet s → v { ( __orset_free_vec . s adds ) ( __orset_free_vec . s tombs ) ( nurl_free # s s ) }

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
@ orset_add *OrSet s i replica i elem → v {
    ( __tag_push . s adds elem replica . s next_seq )
    = . s next_seq + . s next_seq 1
}

// Remove an element: tombstone every currently-observed add-tag for it.
@ orset_remove *OrSet s i elem → v {
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
@ orset_contains *OrSet s i elem → b {
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
// Merge a peer's set (union adds, union tombs) — idempotent, commutative.
@ orset_merge *OrSet a *OrSet b → v {
    ( __merge_tags . a adds . b adds )
    ( __merge_tags . a tombs . b tombs )
}
