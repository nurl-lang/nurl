// stdlib/dist/lease.nu — fencing for side-effecting tasks (§7.5 Phase 12).
//
// During membership convergence two nodes can BRIEFLY both believe they own a
// key. For CRDT state that's harmless — merges commute. But an external side
// effect (write a file, call an API, charge money) executed twice is not.
//
// The fix is the standard fencing-token discipline, enforced at the resource:
//
//   * Ownership EPOCHS — a monotonic epoch per key, bumped on every ring
//     change; a dispatched task carries the epoch it was issued under.
//   * FENCE — the resource remembers the highest epoch it has admitted for a
//     key and REFUSES any execution carrying a lower (stale) epoch. So an old
//     owner that kept dispatching under a stale epoch is fenced out once the
//     new owner (higher epoch) has acted.
//   * IDEMPOTENCY KEYS — the resource also dedups by the task's idempotency
//     key (its task_id), so the SAME task can't fire its effect twice even
//     when the old owner happened to act first and the new owner retries.
//
// Fence (epoch monotonicity) + idempotency (task_id) together give AT-MOST-ONCE
// across a split-ownership window in either ordering. Pure (no side effect)
// handlers never call this and pay zero overhead — they declare themselves
// pure to the job executor.
//
// Idempotency keys are i64 (dist/job task_ids are i64); resource keys are
// opaque bytes (the same key dist/ring shards on). Pure + deterministic.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ __ls_veq ( Vec u ) a ( Vec u ) b → b {
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

@ __ls_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

: LeaseEntry {
    ( Vec u ) key  // resource key
    i token  // highest epoch admitted for this key
    ( Vec i ) applied  // idempotency keys (task_ids) already admitted
}

: LeaseTable {
    ( Vec s ) entries  // *LeaseEntry
}

@ lease_new → *LeaseTable {
    : *LeaseTable t # *LeaseTable ( nurl_alloc Z LeaseTable )
    = . t entries ( vec_new [s] )
    ^ t
}

@ lease_free * LeaseTable t → v {
    : i n ( vec_len [s] . t entries )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . t entries k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *LeaseEntry e # *LeaseEntry pp ( vec_free [u] . e key ) ( vec_free [i] . e applied ) ( nurl_free # s e ) } {}
        = k + k 1
    }
    ( vec_free [s] . t entries )
    ( nurl_free # s t )
}

@ __lease_find * LeaseTable t ( Vec u ) key → s {
    : i n ( vec_len [s] . t entries )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . t entries k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *LeaseEntry e # *LeaseEntry pp ? ( __ls_veq . e key key ) { = found pp } {} } {}
        = k + k 1
    }
    ^ found
}

@ __applied_has ( Vec i ) v i idem → b {
    : i n ( vec_len [i] v )
    : ~ b has F : ~ i k 0
    ~ & ! has < k n { ? == ?? ( vec_get [i] v k ) { T x → x F → -1 } idem { = has T } {} = k + k 1 }
    ^ has
}

// The current (highest admitted) epoch for a key; 0 if never seen.
@ lease_token * LeaseTable t ( Vec u ) key → i {
    : s pp ( __lease_find t key )
    ? == # i pp 0 { ^ 0 } {}
    : *LeaseEntry e # *LeaseEntry pp
    ^ . e token
}

// Admit a side-effecting execution for (key, epoch) with idempotency key
// `idem`. Returns T iff the effect should be performed:
//   * REFUSE if `epoch` is older than the highest epoch admitted for the key
//     (a stale owner, fenced out by a newer one);
//   * else advance the key's epoch to `epoch`, and REFUSE if `idem` was
//     already admitted (duplicate delivery / the same task already ran);
//   * else record `idem` and admit (T).
@ lease_admit * LeaseTable t ( Vec u ) key i epoch i idem → b {
    : s pp ( __lease_find t key )
    ? == # i pp 0 {
        : *LeaseEntry e # *LeaseEntry ( nurl_alloc Z LeaseEntry )
        = . e key ( __ls_cpy key )
        = . e token epoch
        = . e applied ( vec_new [i] )
        ( vec_push [i] . e applied idem )
        ( vec_push [s] . t entries # s e )
        ^ T
    } {}
    : *LeaseEntry e # *LeaseEntry pp
    ? < epoch . e token { ^ F } {}  // stale epoch — fenced out
    = . e token epoch  // advance (epoch >= token)
    ? ( __applied_has . e applied idem ) { ^ F } {}  // duplicate — already ran
    ( vec_push [i] . e applied idem )
    ^ T
}
