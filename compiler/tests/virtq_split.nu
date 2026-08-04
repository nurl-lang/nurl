// virtq_split.nu — Phase A2 test for stdlib/hal/virtq.nu.
//
// Drives the split-ring against an in-memory MOCK DEVICE that plays the
// host side of virtio 1.1 §2.6: it reads `avail`, walks the descriptor
// chain, writes into device-writable segments, and publishes into
// `used`. No MMIO, no hypervisor — the ring is just memory, which is
// exactly what it is on real hardware too (the registers are a separate
// concern, see stdlib/hal/mmio.nu).
//
// The load-bearing cases are the ones that work for thousands of
// buffers and then break:
//   * avail.idx / used.idx are free-running 16-bit counters. They wrap
//     at 65536 and are NOT reduced by the queue size — only the ring
//     SLOT is. A stack that stores the reduced value desynchronises
//     from the device exactly once per 65536 buffers.
//   * Freeing only a chain's head leaks every continuation descriptor,
//     so the queue silently runs dry after a few thousand packets.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/hal/virtq.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

// ── mock device ─────────────────────────────────────────────────
//
// Consumes one available buffer: walks its chain, "writes" `fill`
// bytes worth of length into the first device-writable segment, and
// publishes the head into used with a total written length.

: MockDev { i last_avail }

@ mock_new → *MockDev {
    : *MockDev d # *MockDev ( nurl_alloc Z MockDev )
    = . d last_avail 0
    ^ d
}

@ mock_free * MockDev d → v { ( free d ) }

@ mock_has_work * MockDev d * Virtq q → b {
    ^ ( vq_idx_lt . d last_avail ( virtq_avail_idx q ) )
}

// Returns the chain head it completed, or -1 when idle.
@ mock_service * MockDev d * Virtq q i written → i {
    ? ! ( mock_has_work d q ) { ^ -1 } {}
    : i slot % . d last_avail . q qsize
    : i head ( virtq_avail_ring q slot )
    = . d last_avail ( vq_idx_add . d last_avail 1 )
    // Walk the chain the way a device does, counting its segments.
    : ~ i idx head
    : ~ i n 0
    : ~ b more T
    ~ && more < n . q qsize {
        = n + n 1
        ? == & ( virtq_desc_flags q idx ) ( vq_desc_next ) ( vq_desc_next ) {
            = idx ( virtq_desc_next q idx )
        } { = more F }
    }
    // Publish into used: slot = used.idx % qsize, then bump used.idx.
    : i uslot % ( virtq_used_idx q ) . q qsize
    : i ubase + + ( vq_used_off . q qsize ) 4 * 8 uslot
    : ~ i k 0
    ~ < k 4 {
        : b _a ( vec_set [u] . q mem + ubase k # u & >> head * 8 k 255 )
        : b _b ( vec_set [u] . q mem + + ubase 4 k # u & >> written * 8 k 255 )
        = k + k 1
    }
    : i nidx ( vq_idx_add ( virtq_used_idx q ) 1 )
    : b _c ( vec_set [u] . q mem + ( vq_used_off . q qsize ) 2 # u & nidx 255 )
    : b _d ( vec_set [u] . q mem + ( vq_used_off . q qsize ) 3 # u & >> nidx 8 255 )
    ^ head
}

@ main → i {
    // ── layout arithmetic against the spec ───────────────────────
    ( pb `qsize 8 valid: ` ( virtq_size_valid 8 ) )
    ( pb `qsize 0 invalid: ` ! ( virtq_size_valid 0 ) )
    ( pb `qsize 3 invalid (not a power of two): ` ! ( virtq_size_valid 3 ) )
    ( pb `qsize 32768 valid (spec max): ` ( virtq_size_valid 32768 ) )
    ( pb `qsize 65536 invalid (over max): ` ! ( virtq_size_valid 65536 ) )
    // qsize 8: desc 128, avail at 128 (6+16=22 → used aligned to 4 → 152)
    ( pb `desc table at 0: ` == ( vq_desc_off ) 0 )
    ( pb `avail after 16·qsize: ` == ( vq_avail_off 8 ) 128 )
    ( pb `used is 4-byte aligned: ` == % ( vq_used_off 8 ) 4 0 )
    ( pb `used after avail: ` >= ( vq_used_off 8 ) + 128 22 )
    ( pb `total covers the used ring: ` == ( vq_layout_size 8 ) + ( vq_used_off 8 ) 70 )

    // ── free list ────────────────────────────────────────────────
    : *Virtq q ( virtq_new 8 )
    ( pb `all 8 descriptors free: ` == ( virtq_num_free q ) 8 )
    ( pb `ring starts zeroed: ` && == ( virtq_avail_idx q ) 0 == ( virtq_used_idx q ) 0 )
    : ~ i taken 0
    : ~ b all_distinct T
    : ( Vec i ) seen ( vec_new [i] )
    ~ < taken 8 {
        ?? ( virtq_alloc_desc q ) {
            T d → {
                : ~ i j 0
                ~ < j ( vec_len [i] seen ) {
                    ? == ?? ( vec_get [i] seen j ) { T x → x F → -1 } d { = all_distinct F } {}
                    = j + j 1
                }
                ( vec_push [i] seen d )
            }
            F → { = all_distinct F }
        }
        = taken + taken 1
    }
    ( pb `8 allocations all distinct: ` all_distinct )
    ( pb `queue now empty: ` == ( virtq_num_free q ) 0 )
    ( pb `9th allocation fails: ` ?? ( virtq_alloc_desc q ) { T d → F F → T } )
    // Return them all.
    : ~ i r 0
    ~ < r 8 {
        : i _n ( virtq_free_chain q ?? ( vec_get [i] seen r ) { T x → x F → 0 } )
        = r + r 1
    }
    ( pb `all returned to the free list: ` == ( virtq_num_free q ) 8 )

    // ── single-buffer round trip through the mock device ─────────
    : *MockDev dev ( mock_new )
    ( pb `device idle initially: ` ! ( mock_has_work dev q ) )
    : ?i h1 ( virtq_add_single q 4096 1500 T )
    ( pb `published a buffer: ` ?? h1 { T d → T F → F } )
    ( pb `avail.idx advanced: ` == ( virtq_avail_idx q ) 1 )
    ( pb `one descriptor consumed: ` == ( virtq_num_free q ) 7 )
    ( pb `device sees work: ` ( mock_has_work dev q ) )
    : i head1 ( mock_service dev q 64 )
    ( pb `device completed our head: ` == head1 ?? h1 { T d → d F → -1 } )
    ( pb `used.idx advanced: ` == ( virtq_used_idx q ) 1 )
    ( pb `driver sees a completion: ` ( virtq_has_used q ) )
    : ?i got ( virtq_get_used q )
    ( pb `reaped the same head: ` ?? got { T d → == d head1 F → F } )
    ( pb `written length reported: ` == ( virtq_last_used_len q ) 64 )
    ( pb `nothing left to reap: ` ! ( virtq_has_used q ) )
    : i _f1 ( virtq_free_chain q head1 )
    ( pb `descriptor returned: ` == ( virtq_num_free q ) 8 )

    // Descriptor contents survived the round trip.
    ( pb `desc addr preserved: ` == ( virtq_desc_addr q head1 ) 4096 )
    ( pb `desc len preserved: ` == ( virtq_desc_len q head1 ) 1500 )
    ( pb `device-writable flag set: ` == & ( virtq_desc_flags q head1 ) ( vq_desc_write ) ( vq_desc_write ) )

    // ── a three-segment chain ───────────────────────────────────
    // The shape virtio-net rx uses: a header segment plus data.
    : ?i a0 ( virtq_alloc_desc q )
    : ?i a1 ( virtq_alloc_desc q )
    : ?i a2 ( virtq_alloc_desc q )
    : i d0 ?? a0 { T x → x F → -1 }
    : i d1 ?? a1 { T x → x F → -1 }
    : i d2 ?? a2 { T x → x F → -1 }
    ( virtq_desc_set q d0 8192 12 ( vq_desc_next ) d1 )
    ( virtq_desc_set q d1 8204 1500 | ( vq_desc_next ) ( vq_desc_write ) d2 )
    ( virtq_desc_set q d2 16384 4 ( vq_desc_write ) ( vq_null ) )
    ( virtq_avail_push q d0 )
    ( pb `three descriptors in use: ` == ( virtq_num_free q ) 5 )
    : i head2 ( mock_service dev q 1000 )
    ( pb `device walked to our chain head: ` == head2 d0 )
    : ?i got2 ( virtq_get_used q )
    ( pb `reaped the chain: ` ?? got2 { T d → == d d0 F → F } )
    // THE TRAP: freeing the head alone leaks d1 and d2.
    : i freed ( virtq_free_chain q d0 )
    ( pb `free_chain walked all three: ` == freed 3 )
    ( pb `all descriptors back: ` == ( virtq_num_free q ) 8 )

    // ── 16-bit index arithmetic ─────────────────────────────────
    ( pb `idx_lt basic: ` ( vq_idx_lt 5 9 ) )
    ( pb `idx_lt not reflexive: ` ! ( vq_idx_lt 5 5 ) )
    ( pb `idx wraps: 65530 < 4: ` ( vq_idx_lt 65530 4 ) )
    ( pb `idx wrap not reversed: ` ! ( vq_idx_lt 4 65530 ) )
    ( pb `idx_add wraps: ` == ( vq_idx_add 65535 1 ) 0 )
    ( pb `idx_diff across wrap: ` == ( vq_idx_diff 4 65530 ) 10 )

    // ── the wrap, driven for real ───────────────────────────────
    // Push 70000 buffers through a queue of 8. avail.idx and used.idx
    // both wrap past 65536 more than once. Every one must complete, in
    // order, with the right length — this is the case that separates a
    // correct index discipline from one that works in a demo.
    : i avail_before ( virtq_avail_idx q )
    : ~ i pushed 0
    : ~ i reaped 0
    : ~ b order_ok T
    : ~ b len_ok T
    ~ < pushed 70000 {
        ?? ( virtq_add_single q + 65536 * 4 % pushed 8 128 T ) {
            T d → {
                : i h ( mock_service dev q + 1 % pushed 100 )
                ? != h d { = order_ok F } {}
                ?? ( virtq_get_used q ) {
                    T g → {
                        ? != g d { = order_ok F } {}
                        ? != ( virtq_last_used_len q ) + 1 % pushed 100 { = len_ok F } {}
                        : i _fc ( virtq_free_chain q g )
                        = reaped + reaped 1
                    }
                    F → { = order_ok F }
                }
            }
            F → { = order_ok F }
        }
        = pushed + pushed 1
    }
    ( pb `70000 buffers all completed: ` == reaped 70000 )
    ( pb `every completion matched its head: ` order_ok )
    ( pb `every written length round-tripped: ` len_ok )
    // 70000 pushes past a counter that wraps at 65536: the index must
    // land on (start + 70000) mod 65536, and must NOT be 70000 — the
    // latter is what a driver that never wraps would show.
    ( pb `avail.idx wrapped correctly: ` == ( virtq_avail_idx q ) % + avail_before 70000 65536 )
    ( pb `and did wrap (idx < pushes): ` < ( virtq_avail_idx q ) 70000 )
    ( pb `queue is whole again: ` == ( virtq_num_free q ) 8 )

    // ── hostile device: a completion id outside the table ────────
    // A broken or malicious device reporting id >= qsize must not be
    // let through: that id would go onto the free list and corrupt the
    // descriptor table on the next allocation.
    : i ubase + + ( vq_used_off . q qsize ) 4 * 8 % ( virtq_used_idx q ) . q qsize
    : b _h1 ( vec_set [u] . q mem ubase # u 99 )
    : b _h2 ( vec_set [u] . q mem + ubase 1 # u 0 )
    : b _h3 ( vec_set [u] . q mem + ubase 2 # u 0 )
    : b _h4 ( vec_set [u] . q mem + ubase 3 # u 0 )
    : i bad_idx ( vq_idx_add ( virtq_used_idx q ) 1 )
    : b _h5 ( vec_set [u] . q mem + ( vq_used_off . q qsize ) 2 # u & bad_idx 255 )
    : b _h6 ( vec_set [u] . q mem + ( vq_used_off . q qsize ) 3 # u & >> bad_idx 8 255 )
    ( pb `out-of-range used id refused: ` ?? ( virtq_get_used q ) { T d → F F → T } )
    ( pb `free list not corrupted: ` == ( virtq_num_free q ) 8 )

    // ── notification suppression ────────────────────────────────
    ( pb `notify needed by default: ` ( virtq_needs_notify q ) )
    : b _n1 ( vec_set [u] . q mem ( vq_used_off . q qsize ) # u ( vq_used_no_notify ) )
    ( pb `device NO_NOTIFY honoured: ` ! ( virtq_needs_notify q ) )
    ( virtq_set_avail_flags q ( vq_avail_no_interrupt ) )
    ( pb `avail NO_INTERRUPT set (polling driver): ` == ( virtq_avail_flags q ) ( vq_avail_no_interrupt ) )

    ( mock_free dev )
    ( virtq_free q )
    ( vec_free [i] seen )
    ^ 0
}
