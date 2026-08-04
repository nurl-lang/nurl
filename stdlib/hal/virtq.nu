// stdlib/hal/virtq.nu — virtio split-ring virtqueue, as pure logic.
//
// PURE. The ring is a byte region the caller owns; this module only
// reads and writes it. No MMIO, no allocation of device memory, no
// notification — those are the driver's job (see `stdlib/hal/mmio.nu`
// for the register side). That split is what lets the ring be driven
// against an in-memory mock device in a unit test on the host, and
// against a real device on a freestanding target, with the same code.
//
// It lives in hal/ rather than net/ because a virtqueue is not a
// networking concept: the same ring carries console, block and RNG
// traffic. net/ gets the virtio-net *device* logic later; this is the
// transport underneath it.
//
// ── LAYOUT (virtio 1.1 §2.6, VERSION_1 / "modern") ──────────────
//
//   descriptor table   16 · qsize bytes   (le64 addr, le32 len,
//                                          le16 flags, le16 next)
//   available ring      6 + 2 · qsize     (le16 flags, le16 idx,
//                                          le16 ring[qsize], le16 used_event)
//   used ring           6 + 8 · qsize     (le16 flags, le16 idx,
//                                          {le32 id, le32 len}[qsize],
//                                          le16 avail_event)
//
// Everything is LITTLE-ENDIAN regardless of host byte order — that is
// what VERSION_1 buys, and it is why this module uses the `_le`
// accessors throughout. A legacy (pre-1.0) device would use guest
// order instead; we do not negotiate legacy, so guest order never
// enters the picture.
//
// The three regions are laid out contiguously here with the alignment
// the spec requires (desc 16, avail 2, used 4). A driver that allocates
// them separately can pass the offsets in instead.
//
// ── WRAPPING IS THE TRAP ────────────────────────────────────────
//
// `avail.idx` and `used.idx` are free-running 16-bit counters: they
// wrap at 65536 and are NOT reduced modulo the queue size. Only the
// ring *slot* is `idx % qsize`. Code that stores the reduced value into
// idx works perfectly until the 65536th buffer and then desynchronises
// from the device forever. Every comparison here is therefore done on
// the 16-bit difference, never on raw magnitudes — the same discipline
// as TCP sequence numbers in net/tcpseg.nu.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// ── descriptor flags (virtio 1.1 §2.6.5) ────────────────────────

@ vq_desc_next → i { ^ 1 }  // buffer continues in `next`

@ vq_desc_write → i { ^ 2 }  // device writes it (else driver writes)

@ vq_desc_indirect → i { ^ 4 }  // buffer is an indirect descriptor table

// avail.flags: ask the device not to interrupt us. With a polling
// driver (the unikernel plan's v1 execution model) this is set once at
// setup and never cleared.
@ vq_avail_no_interrupt → i { ^ 1 }

// used.flags: the device telling us not to notify it.
@ vq_used_no_notify → i { ^ 1 }

@ vq_desc_size → i { ^ 16 }

// A free-list terminator that cannot be a valid descriptor index,
// since qsize is capped at 32768 by the spec.
@ vq_null → i { ^ 65535 }

// ── layout arithmetic ───────────────────────────────────────────

@ __align_up i n i a → i { ^ * / + n - a 1 a a }

@ vq_desc_off → i { ^ 0 }

@ vq_avail_off i qsize → i { ^ ( __align_up * 16 qsize 2 ) }

@ vq_used_off i qsize → i {
    ^ ( __align_up + ( vq_avail_off qsize ) + 6 * 2 qsize 4 )
}

@ vq_layout_size i qsize → i {
    ^ + ( vq_used_off qsize ) + 6 * 8 qsize
}

// ── the queue ───────────────────────────────────────────────────

: Virtq {
    i qsize
    ( Vec u ) mem  // the whole ring region
    i free_head  // head of the driver-side free descriptor list
    i num_free
    i last_used  // free-running: the used.idx we have consumed up to
    i avail_shadow  // our own copy of avail.idx (the device may not be trusted)
}

// `qsize` must be a power of two, 1..32768 (spec §2.6). Returns a
// queue whose descriptors are all on the free list.
@ virtq_new i qsize → *Virtq {
    : *Virtq q # *Virtq ( nurl_alloc Z Virtq )
    = . q qsize qsize
    = . q mem ( vec_with_cap [u] ( vq_layout_size qsize ) )
    : ~ i k 0
    ~ < k ( vq_layout_size qsize ) { ( vec_push [u] . q mem # u 0 ) = k + k 1 }
    = . q free_head 0
    = . q num_free qsize
    = . q last_used 0
    = . q avail_shadow 0
    // Chain every descriptor onto the free list via its `next` field.
    : ~ i d 0
    ~ < d qsize {
        ( __vq_set_next q d ? == d - qsize 1 ( vq_null ) + d 1 )
        = d + d 1
    }
    ^ q
}

@ virtq_free * Virtq q → v {
    ( vec_free [u] . q mem )
    ( free q )
}

// Is `n` a power of two in the range the spec allows?
@ virtq_size_valid i n → b {
    ? || < n 1 > n 32768 { ^ F } {}
    ^ == & n - n 1 0
}

// ── raw field accessors ─────────────────────────────────────────

@ __vq_w16 * Virtq q i off i val → v {
    : b _a ( vec_set [u] . q mem off # u & val 255 )
    : b _b ( vec_set [u] . q mem + off 1 # u & >> val 8 255 )
}

@ __vq_r16 * Virtq q i off → i {
    ^ ?? ( bytes_read_u16_le . q mem off ) { T x → # i x F → 0 }
}

@ __vq_w32 * Virtq q i off i val → v {
    : ~ i k 0
    ~ < k 4 {
        : b _s ( vec_set [u] . q mem + off k # u & >> val * 8 k 255 )
        = k + k 1
    }
}

@ __vq_r32 * Virtq q i off → i {
    ^ ?? ( bytes_read_u32_le . q mem off ) { T x → # i x F → 0 }
}

@ __vq_w64 * Virtq q i off i val → v {
    : ~ i k 0
    ~ < k 8 {
        : b _s ( vec_set [u] . q mem + off k # u & >> val * 8 k 255 )
        = k + k 1
    }
}

@ __vq_r64 * Virtq q i off → i {
    ^ ?? ( bytes_read_u64_le . q mem off ) { T x → # i x F → 0 }
}

@ __vq_desc_base i idx → i { ^ * 16 idx }

@ __vq_set_next * Virtq q i idx i next → v {
    ( __vq_w16 q + ( __vq_desc_base idx ) 14 next )
}

@ virtq_desc_addr * Virtq q i idx → i { ^ ( __vq_r64 q ( __vq_desc_base idx ) ) }

@ virtq_desc_len * Virtq q i idx → i { ^ ( __vq_r32 q + ( __vq_desc_base idx ) 8 ) }

@ virtq_desc_flags * Virtq q i idx → i { ^ ( __vq_r16 q + ( __vq_desc_base idx ) 12 ) }

@ virtq_desc_next * Virtq q i idx → i { ^ ( __vq_r16 q + ( __vq_desc_base idx ) 14 ) }

@ virtq_avail_flags * Virtq q → i { ^ ( __vq_r16 q ( vq_avail_off . q qsize ) ) }

@ virtq_set_avail_flags * Virtq q i flags → v {
    ( __vq_w16 q ( vq_avail_off . q qsize ) flags )
}

@ virtq_avail_idx * Virtq q → i { ^ ( __vq_r16 q + ( vq_avail_off . q qsize ) 2 ) }

@ virtq_avail_ring * Virtq q i slot → i {
    ^ ( __vq_r16 q + + ( vq_avail_off . q qsize ) 4 * 2 slot )
}

@ virtq_used_flags * Virtq q → i { ^ ( __vq_r16 q ( vq_used_off . q qsize ) ) }

@ virtq_used_idx * Virtq q → i { ^ ( __vq_r16 q + ( vq_used_off . q qsize ) 2 ) }

@ virtq_used_id * Virtq q i slot → i {
    ^ ( __vq_r32 q + + ( vq_used_off . q qsize ) 4 * 8 slot )
}

@ virtq_used_len * Virtq q i slot → i {
    ^ ( __vq_r32 q + + + ( vq_used_off . q qsize ) 4 * 8 slot 4 )
}

// ── 16-bit index arithmetic ─────────────────────────────────────
//
// idx counters wrap at 65536 and are never reduced by qsize. Compare
// via the signed 16-bit difference, exactly as TCP compares sequence
// numbers — a raw `<` breaks once per 65536 buffers.

@ vq_idx_diff i a i b → i {
    : i d & - a b 65535
    ^ ? >= d 32768 - d 65536 d
}

@ vq_idx_lt i a i b → b { ^ < ( vq_idx_diff a b ) 0 }

@ vq_idx_add i a i n → i { ^ & + a n 65535 }

// ── descriptor allocation ───────────────────────────────────────

// Take one descriptor off the free list.
@ virtq_alloc_desc * Virtq q → ?i {
    ? <= . q num_free 0 { ^ @ ?i { F 0 } } {}
    : i head . q free_head
    ? == head ( vq_null ) { ^ @ ?i { F 0 } } {}
    = . q free_head ( virtq_desc_next q head )
    = . q num_free - . q num_free 1
    ^ @ ?i { T head }
}

// Return a whole chain to the free list, following NEXT links. The
// chain — not just its head — is what the device hands back, so
// freeing only the head leaks every continuation descriptor and the
// queue silently runs dry after a few thousand packets.
@ virtq_free_chain * Virtq q i head → i {
    : ~ i idx head
    : ~ i n 0
    : ~ b more T
    ~ && more < n . q qsize {
        : i nxt ( virtq_desc_next q idx )
        : i flags ( virtq_desc_flags q idx )
        ( __vq_set_next q idx . q free_head )
        = . q free_head idx
        = . q num_free + . q num_free 1
        = n + n 1
        ? == & flags ( vq_desc_next ) ( vq_desc_next ) { = idx nxt } { = more F }
    }
    ^ n
}

@ virtq_num_free * Virtq q → i { ^ . q num_free }

// ── publishing buffers ──────────────────────────────────────────

// Describe one buffer segment into descriptor `idx`. `addr` is the
// address the DEVICE will use, i.e. a physical address — translation
// is the driver's job (identity-mapped in the unikernel's v1).
@ virtq_desc_set * Virtq q i idx i addr i len i flags i next → v {
    ( __vq_w64 q ( __vq_desc_base idx ) addr )
    ( __vq_w32 q + ( __vq_desc_base idx ) 8 len )
    ( __vq_w16 q + ( __vq_desc_base idx ) 12 flags )
    ( __vq_w16 q + ( __vq_desc_base idx ) 14 next )
}

// Publish a chain head into the available ring and advance avail.idx.
//
// ORDER MATTERS: the ring slot must be written BEFORE idx is bumped,
// or the device may read a slot we have not filled in. On a real target
// a write barrier belongs between the two; here the sequence is at
// least correct in program order, and the driver adds the fence.
@ virtq_avail_push * Virtq q i head → v {
    : i slot % . q avail_shadow . q qsize
    ( __vq_w16 q + + ( vq_avail_off . q qsize ) 4 * 2 slot head )
    = . q avail_shadow ( vq_idx_add . q avail_shadow 1 )
    ( __vq_w16 q + ( vq_avail_off . q qsize ) 2 . q avail_shadow )
}

// Convenience: allocate, describe and publish a single-segment buffer.
// Returns the descriptor index, or None when the queue is full.
@ virtq_add_single * Virtq q i addr i len b device_writes → ?i {
    ^ ?? ( virtq_alloc_desc q ) {
        T d → {
            ( virtq_desc_set q d addr len ? device_writes ( vq_desc_write ) 0 ( vq_null ) )
            ( virtq_avail_push q d )
            @ ?i { T d }
        }
        F → @ ?i { F 0 }
    }
}

// ── reaping completions ─────────────────────────────────────────

// Has the device completed anything we have not consumed?
@ virtq_has_used * Virtq q → b {
    ^ ( vq_idx_lt . q last_used ( virtq_used_idx q ) )
}

// Consume one completion. Returns the chain head; the caller reads the
// written length with `virtq_last_used_len` before the next call.
// Does NOT free the chain — the caller may still need the buffer, and
// freeing is a separate, explicit step.
@ virtq_get_used * Virtq q → ?i {
    ? ! ( virtq_has_used q ) { ^ @ ?i { F 0 } } {}
    : i slot % . q last_used . q qsize
    : i id ( virtq_used_id q slot )
    // A device that reports an out-of-range id is broken or hostile;
    // refusing it keeps a bad id out of the free list, where it would
    // corrupt the descriptor table on the next allocation.
    ? >= id . q qsize { ^ @ ?i { F 0 } } {}
    = . q last_used ( vq_idx_add . q last_used 1 )
    ^ @ ?i { T id }
}

// Bytes the device wrote for the completion most recently returned by
// `virtq_get_used`.
@ virtq_last_used_len * Virtq q → i {
    : i slot % ( vq_idx_add . q last_used 65535 ) . q qsize
    ^ ( virtq_used_len q slot )
}

// Should the driver kick the device after publishing? The device sets
// NO_NOTIFY when it is already polling; honouring it is a pure
// throughput win, and getting it wrong the other way (never notifying)
// stalls the queue.
@ virtq_needs_notify * Virtq q → b {
    ^ != & ( virtq_used_flags q ) ( vq_used_no_notify ) ( vq_used_no_notify )
}
