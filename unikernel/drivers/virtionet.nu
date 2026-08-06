// unikernel/drivers/virtionet.nu — frames in, frames out, over a real
// device.
//
// This is the glue B5 exists to write, and it is deliberately thin:
// the ring bookkeeping is `hal/virtq.nu` (A2, mutation-tested), the
// register protocol is `hal/virtio.nu` (B5.0, tested against a
// buffer), and everything above the frame is the sans-IO stack in
// `net/`. What is left for this file is the part that can only be
// written where the hardware is — buffers, their physical addresses,
// and the two queues' rhythm.
//
// PHYSICAL ADDRESSES. The device is a bus master: it does not go
// through our page tables, so every address it is handed must be
// physical. The guest identity-maps the low 4 GiB, so virtual equals
// physical here — and saying that out loud is the point, because it is
// a property of this target and not of virtio. When B2's memory work
// grows a mapping that is not the identity, every `# i ( vec_data … )`
// below becomes a translation, and they are all in this file.
//
// THE HEADER. With exactly VIRTIO_F_VERSION_1 negotiated and no
// device-specific bits, every packet carries a fixed 12-byte
// `virtio_net_hdr`: all zeros on transmit, ignorable on receive. No
// checksum offload, no TSO, no MRG_RXBUF — every checksum is computed
// by the pure stack, which is what it was built for.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtq.nu`
$ `stdlib/hal/virtio.nu`

& `c` @ nurl_boot_cmdline → s

// virtio-net's queue 0 is receive, queue 1 is transmit (spec §5.1.2).
@ vnet_rxq → i { ^ 0 }

@ vnet_txq → i { ^ 1 }

// The modern header, fixed size, zero-filled on transmit.
@ vnet_hdr_len → i { ^ 12 }

// One receive buffer per descriptor: no MRG_RXBUF was negotiated, so
// the device puts each frame in exactly one buffer and a frame that
// does not fit is dropped by the device rather than split. 2048 holds
// the header plus a 1500-byte MTU with room to spare.
@ vnet_buf_len → i { ^ 2048 }

// What is left for a frame once the 12-byte header has its share. Both
// directions are bounded by it: a frame longer than this cannot be
// transmitted (it is refused, not truncated), and a device that claims
// to have written more than this into a 2048-byte buffer is not
// believed.
@ vnet_max_frame → i { ^ 2036 }

// A Vec is a value — a handle struct, not a pointer — so a pool of
// them is a pool of heap copies of the handle. Boxing says that once,
// here, instead of at every push.
: VecBox { ( Vec u ) v }

@ __vec_box ( Vec u ) v → i {
    : *VecBox bx # *VecBox ( nurl_alloc Z VecBox )
    = . bx v v
    ^ # i bx
}

: VirtioNet {
    i base
    i mac  // read from config space, big-endian in the wire sense
    * Virtq rx
    * Virtq tx
    ( Vec i ) rxbuf  // one *(Vec u) per descriptor, as an integer
    ( Vec i ) txbuf
    i rx_posted
    b ready
}

@ __cfg_u8 i base i off → i {
    // Config space is byte-addressable; a 32-bit read at the aligned
    // word and a shift is what a device that only answers word reads
    // needs, and works either way.
    : i word ( mmio_read32 + + base ( vio_reg_config ) & off ~ 3 )
    ^ & >> word * 8 & off 3 255
}

// Six bytes of MAC, most significant first, packed into an integer the
// way net/eth.nu spells one.
@ __read_mac i base → i {
    : ~ i m 0
    : ~ i k 0
    ~ < k 6 {
        = m | << m 8 ( __cfg_u8 base k )
        = k + k 1
    }
    ^ m
}

@ __buf_new i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    ^ v
}

@ __buf_phys ( Vec u ) v → i { ^ # i ( vec_data [u] v ) }

@ __vq_phys * Virtq q i off → i { ^ + # i ( vec_data [u] . q mem ) off }

// Find the first virtio-net device the command line names, bring it
// up, and hand back a driver with both queues live. A null pointer
// means there is no such device — which is a fact about the machine,
// not an error, and the caller decides what to do about it.
@ vnet_open i qsize → *VirtioNet {
    : s cl ( nurl_boot_cmdline )
    : i n ( virtio_mmio_count cl )
    : ~ i k 0
    ~ < k n {
        : VioMmioDev d ( virtio_mmio_from_cmdline cl k )
        ? == ( virtio_probe . d base ) ( vio_id_net ) {
            : *VirtioNet nic ( __vnet_bring_up . d base qsize )
            ? != # i nic 0 { ^ nic } {}
        } {}
        = k + k 1
    }
    ^ # *VirtioNet 0
}

@ __vnet_bring_up i base i qsize → *VirtioNet {
    // No device-specific features: not even MAC. The address is read
    // from config space either way, and a feature this driver does not
    // implement is a format it would then have to parse.
    ? ! ( virtio_init base 0 ) { ^ # *VirtioNet 0 } {}

    : i maxq ( virtio_queue_max base ( vnet_rxq ) )
    ? == maxq 0 { ^ # *VirtioNet 0 } {}
    : i qs ? > qsize maxq maxq qsize

    : *VirtioNet nic # *VirtioNet ( nurl_alloc Z VirtioNet )
    = . nic base base
    = . nic mac ( __read_mac base )
    = . nic rx ( virtq_new qs )
    = . nic tx ( virtq_new qs )
    = . nic rxbuf ( vec_new [i] )
    = . nic txbuf ( vec_new [i] )
    = . nic rx_posted 0
    = . nic ready F

    ? ! ( __queue_live base ( vnet_rxq ) . nic rx qs ) { ^ nic } {}
    ? ! ( __queue_live base ( vnet_txq ) . nic tx qs ) { ^ nic } {}

    // DRIVER_OK last, and only once both queues are live: it is the
    // driver telling the device it may start using them, and a device
    // that starts using a queue that is not there writes into whatever
    // address the register still held.
    ( virtio_driver_ok base )
    = . nic ready T
    ( __rx_refill nic )
    ^ nic
}

@ __queue_live i base i qidx * Virtq q i qs → b {
    ^ ( virtio_queue_setup base qidx qs
    ( __vq_phys q ( vq_desc_off ) )
    ( __vq_phys q ( vq_avail_off qs ) )
    ( __vq_phys q ( vq_used_off qs ) ) )
}

@ vnet_ready * VirtioNet nic → b {
    ? == # i nic 0 { ^ F } {}
    ^ . nic ready
}

@ vnet_mac * VirtioNet nic → i {
    ? == # i nic 0 { ^ 0 } {}
    ^ . nic mac
}

// Fill the receive queue once, at bring-up. Every descriptor the device
// completes is handed straight back with the same buffer (see vnet_rx),
// so the pool is allocated here and never grows: a driver that allocates
// per packet is a driver that stops working under load, which is exactly
// when it matters.
//
// The loop is bounded by the queue rather than by "until something
// fails". `num_free > 0` and "the last add worked" are two different
// conditions, and a version that trusted the first one spun for ever the
// moment they disagreed.
@ __rx_refill * VirtioNet nic → i {
    : ~ i added 0
    : ~ i tries 0
    : i limit . . nic rx qsize
    ~ && < tries limit > ( virtq_num_free . nic rx ) 0 {
        = tries + tries 1
        : ( Vec u ) b ( __buf_new ( vnet_buf_len ) )
        : ~ b ok F
        ?? ( virtq_add_single . nic rx ( __buf_phys b ) ( vnet_buf_len ) T ) {
            T _d → {
                ( vec_push [i] . nic rxbuf ( __vec_box b ) )
                = added + added 1
                = ok T
            }
            F → {
                ( vec_free [u] b )
                = ok F
            }
        }
        ? ! ok { = tries limit } {}
    }
    ? > added 0 { ( virtio_notify . nic base ( vnet_rxq ) ) } {}
    ^ added
}

// One received frame, or 0 bytes. The 12-byte header is stripped here
// — nothing above this file has any use for it, and a stack that had
// to skip it would be a stack that knows which device it is on.
@ vnet_rx * VirtioNet nic ( Vec u ) out → i {
    ? ! ( vnet_ready nic ) { ^ 0 } {}
    ?? ( virtq_get_used . nic rx ) {
        T head → {
            : i len ( virtq_last_used_len . nic rx )
            : i addr ( virtq_desc_addr . nic rx head )
            // The length is the DEVICE's number, and the buffer is ours.
            // A device that reports more than it was given a place to
            // write is broken or hostile either way, and copying what it
            // claims would read past the end of the buffer into whatever
            // the allocator put next. Clamp, and let the frame be short:
            // the stack above checks lengths again from the IP header.
            : ~ i n ? > len ( vnet_hdr_len ) - len ( vnet_hdr_len ) 0
            ? > n ( vnet_max_frame ) { = n ( vnet_max_frame ) } {}
            ? > n 0 {
                ( bytes_extend_raw out # s + addr ( vnet_hdr_len ) n )
            } {}
            // Hand the descriptor straight back: the buffer is still
            // ours and still the right size.
            ( virtq_desc_set . nic rx head addr ( vnet_buf_len ) 2 ( vq_null ) )
            ( virtq_avail_push . nic rx head )
            ( virtio_notify . nic base ( vnet_rxq ) )
            ^ n
        }
        F → 0
    }
}

// The transmit buffer belonging to descriptor `d`, allocated the first
// time that descriptor is used and kept for ever after.
//
// THE POOL IS INDEXED BY DESCRIPTOR, and that is the whole fix. The
// version this replaces allocated a fresh buffer for every frame and
// pushed it onto a list that only `vnet_close` ever emptied: the device
// finished with the buffer, the descriptor went back on the free list,
// and the two kilobytes stayed allocated. A server leaked them at line
// rate — which is a leak nobody sees in a demo that answers one request
// and nobody survives in a machine that answers a million.
@ __tx_buffer * VirtioNet nic i d → ( Vec u ) {
    ~ <= ( vec_len [i] . nic txbuf ) d { ( vec_push [i] . nic txbuf 0 ) }
    : i cur ?? ( vec_get [i] . nic txbuf d ) { T x → x F → 0 }
    ? != cur 0 {
        : *VecBox bx # *VecBox cur
        ^ . bx v
    } {}
    : ( Vec u ) fresh ( __buf_new ( vnet_buf_len ) )
    : i boxed ( __vec_box fresh )
    : b _set ( vec_set [i] . nic txbuf d boxed )
    : *VecBox nbx # *VecBox boxed
    ^ . nbx v
}

// Send one frame: header and payload in one buffer, one descriptor.
//
// A frame longer than the buffer is REFUSED rather than truncated. The
// stack above never builds one — the MTU is 1500 and the buffer holds
// 2036 — so this is the answer to a bug elsewhere, and "the send failed"
// is a fact its caller can act on where "the peer got half a packet" is
// not.
@ vnet_tx * VirtioNet nic ( Vec u ) frame i off i len → b {
    ? ! ( vnet_ready nic ) { ^ F } {}
    ? <= len 0 { ^ F } {}
    ? > len ( vnet_max_frame ) { ^ F } {}
    ( __tx_reap nic )

    // The descriptor comes first: the buffer is chosen by its index, and
    // publishing a descriptor before its buffer is filled would hand the
    // device the previous frame's bytes.
    ?? ( virtq_alloc_desc . nic tx ) {
        T d → {
            : ( Vec u ) pkt ( __tx_buffer nic d )
            : ~ i k 0
            ~ < k len {
                : b _ok ( vec_set [u] pkt + ( vnet_hdr_len ) k
                ?? ( vec_get [u] frame + off k ) { T x → x F → # u 0 } )
                = k + k 1
            }
            ( virtq_desc_set . nic tx d ( __buf_phys pkt ) + ( vnet_hdr_len ) len 0 ( vq_null ) )
            ( virtq_avail_push . nic tx d )
            ( virtio_notify . nic base ( vnet_txq ) )
            ^ T
        }
        F → ^ F
    }
}

// Reclaim descriptors the device has finished transmitting. The
// buffers stay in the pool: they are reused by index, and freeing one
// the device has not finished with is the bug this reaping exists to
// avoid.
@ __tx_reap * VirtioNet nic → i {
    : ~ i n 0
    ~ ( virtq_has_used . nic tx ) {
        ?? ( virtq_get_used . nic tx ) {
            T head → {
                : i _f ( virtq_free_chain . nic tx head )
                = n + n 1
            }
            F → { ^ n }
        }
    }
    ^ n
}

@ vnet_close * VirtioNet nic → v {
    ? == # i nic 0 { ^ } {}
    ( virtio_reset . nic base )
    ( __free_pool . nic rxbuf )
    ( __free_pool . nic txbuf )
    ( vec_free [i] . nic rxbuf )
    ( vec_free [i] . nic txbuf )
    ( virtq_free . nic rx )
    ( virtq_free . nic tx )
    ( nurl_free # s nic )
}

@ __free_pool ( Vec i ) pool → v {
    : i n ( vec_len [i] pool )
    : ~ i k 0
    ~ < k n {
        : *VecBox b # *VecBox ?? ( vec_get [i] pool k ) { T x → x F → 0 }
        ? != # i b 0 {
            ( vec_free [u] . b v )
            ( nurl_free # s b )
        } {}
        = k + k 1
    }
}
