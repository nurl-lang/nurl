// unikernel/drivers/virtioblk.nu — sectors in, sectors out, over a real
// device.
//
// The same shape as `drivers/virtionet.nu` and for the same reason: the
// ring bookkeeping is `hal/virtq.nu`, the register protocol is
// `hal/virtio.nu`, and what is left here is the part that can only be
// written where the hardware is. virtio-blk is the simpler of the two —
// ONE queue, and a request is three descriptors: a header the driver
// writes, the data, and one status byte the device writes.
//
// SYNCHRONOUS ON PURPOSE. Every request is submitted and then waited
// for. A filesystem call is already a blocking call in every caller
// above it, the guest has one vCPU, and an asynchronous block layer
// would buy queue depth that a cooperative scheduler with one core has
// nothing to do with. What it would cost is a completion path that runs
// while a filesystem is halfway through a directory — which is the bug
// class this avoids entirely rather than manages.
//
// PHYSICAL ADDRESSES. The device is a bus master and does not go
// through our page tables. The guest identity-maps the low 4 GiB, so
// virtual equals physical here, and the caller's own buffer is handed
// straight to the device — no bounce, no copy. When a mapping that is
// not the identity appears, every `# i ( vec_data … )` and every raw
// pointer below becomes a translation, and they are all in this file.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtq.nu`
$ `stdlib/hal/virtio.nu`

& `c` @ nurl_boot_cmdline → s

// virtio-blk has exactly one queue: requests in, completions out.
@ vblk_q → i { ^ 0 }

@ vblk_type_in → i { ^ 0 }

@ vblk_type_out → i { ^ 1 }

@ vblk_type_flush → i { ^ 4 }

@ vblk_hdr_len → i { ^ 16 }

// The request unit is 512 bytes REGARDLESS of what the device reports
// as its logical block size: `sector` in a request header counts
// 512-byte units (spec 1.1 §5.2.6). A driver that scaled by `blk_size`
// would address the right byte on a 512-byte device and eight times too
// far on a 4096-byte one.
@ vblk_sector → i { ^ 512 }

// The feature bits this driver knows about.
@ vblk_f_ro → i { ^ 32 }  // bit 5: the device refuses writes
@ vblk_f_flush → i { ^ 512 }  // bit 9: the device has a cache to flush

: VirtioBlk {
    i base
    * Virtq q
    ( Vec u ) hdr
    ( Vec u ) st
    i capacity  // in 512-byte sectors
    b flush_ok
    b readonly
    b ready
}

@ __cfg8 i base i off → i {
    : i word ( mmio_read32 + + base ( vio_reg_config ) & off ~ 3 )
    ^ & >> word * 8 & off 3 255
}

// Capacity is a 64-bit little-endian count of 512-byte sectors at
// config offset 0.
@ __read_capacity i base → i {
    : ~ i c 0
    : ~ i k 0
    ~ < k 8 {
        = c | c << ( __cfg8 base k ) * 8 k
        = k + k 1
    }
    ^ c
}

@ __phys ( Vec u ) v → i { ^ # i ( vec_data [u] v ) }

@ __vq_phys * Virtq q i off → i { ^ + # i ( vec_data [u] . q mem ) off }

// Find the first virtio-blk device the command line names and bring it
// up. A null pointer means there is no such device — a fact about the
// machine, not an error.
@ vblk_open i qsize → *VirtioBlk {
    : s cl ( nurl_boot_cmdline )
    : i n ( virtio_mmio_count cl )
    : ~ i k 0
    ~ < k n {
        : VioMmioDev d ( virtio_mmio_from_cmdline cl k )
        ? == ( virtio_probe . d base ) ( vio_id_block ) {
            : *VirtioBlk b ( __vblk_bring_up . d base qsize )
            ? != # i b 0 { ^ b } {}
        } {}
        = k + k 1
    }
    ^ # *VirtioBlk 0
}

@ __vblk_bring_up i base i qsize → *VirtioBlk {
    // What the device offers decides what we ask for. FLUSH is the one
    // that matters: without it there is no way to make a write durable,
    // and a filesystem promising `fsync` over a device that cannot do
    // it would be promising something nobody can deliver. Asking for a
    // bit the device does not offer is harmless — the negotiation ANDs
    // them — but knowing WHICH we got is not, so it is read here.
    : i offered ( virtio_device_features base 0 )
    : b has_flush != 0 & offered ( vblk_f_flush )
    : b is_ro != 0 & offered ( vblk_f_ro )
    : i want ? has_flush ( vblk_f_flush ) 0

    ? ! ( virtio_init base want ) { ^ # *VirtioBlk 0 } {}

    : i maxq ( virtio_queue_max base ( vblk_q ) )
    ? == maxq 0 { ^ # *VirtioBlk 0 } {}
    : i qs ? > qsize maxq maxq qsize
    // Three descriptors go into one request, so a queue shorter than
    // that can never carry one.
    ? < qs 4 { ^ # *VirtioBlk 0 } {}

    : *VirtioBlk d # *VirtioBlk ( nurl_alloc Z VirtioBlk )
    = . d base base
    = . d q ( virtq_new qs )
    = . d hdr ( __zeros ( vblk_hdr_len ) )
    = . d st ( __zeros 1 )
    = . d capacity ( __read_capacity base )
    = . d flush_ok has_flush
    = . d readonly is_ro
    = . d ready F

    ? ! ( virtio_queue_setup base ( vblk_q ) qs
    ( __vq_phys . d q ( vq_desc_off ) )
    ( __vq_phys . d q ( vq_avail_off qs ) )
    ( __vq_phys . d q ( vq_used_off qs ) ) ) { ^ d } {}

    ( virtio_driver_ok base )
    = . d ready T
    ^ d
}

@ __zeros i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    ^ v
}

@ vblk_ready * VirtioBlk d → b {
    ? == # i d 0 { ^ F } {}
    ^ . d ready
}

@ vblk_capacity * VirtioBlk d → i {
    ? ! ( vblk_ready d ) { ^ 0 } {}
    ^ . d capacity
}

@ vblk_readonly * VirtioBlk d → b {
    ? == # i d 0 { ^ T } {}
    ^ . d readonly
}

@ __put_hdr * VirtioBlk d i type i sector → v {
    : ~ i k 0
    ~ < k ( vblk_hdr_len ) { : b _z ( vec_set [u] . d hdr k # u 0 ) = k + k 1 }
    = k 0
    ~ < k 4 { : b _t ( vec_set [u] . d hdr k # u & >> type * 8 k 255 ) = k + k 1 }
    = k 0
    ~ < k 8 { : b _s ( vec_set [u] . d hdr + 8 k # u & >> sector * 8 k 255 ) = k + k 1 }
}

// One request, submitted and waited for. `buf` may be 0 for a request
// with no data (FLUSH), in which case the chain is two descriptors.
//
// The three descriptors are allocated BEFORE anything is published: a
// partially built chain on the available ring is a chain the device
// will follow into whatever the `next` field happened to hold.
@ __request * VirtioBlk d i type i sector s buf i nbytes b dev_writes → b {
    ? ! ( vblk_ready d ) { ^ F } {}
    : b has_data && != 0 # i buf > nbytes 0

    : ~ i dh - 0 1
    : ~ i dd - 0 1
    : ~ i ds - 0 1
    ?? ( virtq_alloc_desc . d q ) { T x → = dh x F → ^ F }
    ? has_data {
        ?? ( virtq_alloc_desc . d q ) {
            T x → = dd x
            F → { : i _f ( virtq_free_chain . d q dh ) ^ F }
        }
    } {}
    ?? ( virtq_alloc_desc . d q ) {
        T x → = ds x
        F → {
            : i _f ( virtq_free_chain . d q dh )
            ? has_data { : i _g ( virtq_free_chain . d q dd ) } {}
            ^ F
        }
    }

    ( __put_hdr d type sector )
    : b _s ( vec_set [u] . d st 0 # u 255 )

    ( virtq_desc_set . d q dh ( __phys . d hdr ) ( vblk_hdr_len ) ( vq_desc_next )
    ? has_data dd ds )
    ? has_data {
        ( virtq_desc_set . d q dd # i buf nbytes
        | ( vq_desc_next ) ? dev_writes ( vq_desc_write ) 0 ds )
    } {}
    ( virtq_desc_set . d q ds ( __phys . d st ) 1 ( vq_desc_write ) ( vq_null ) )

    ( virtq_avail_push . d q dh )
    ( virtio_notify . d base ( vblk_q ) )

    // Spin, but not for ever: a device that never completes a request
    // is a machine that hangs with no message, and "the disk stopped
    // answering" is something a caller can report where a freeze is
    // not. The bound is large because it is a backstop, not a timeout.
    : ~ i spins 0
    : ~ b done F
    ~ && ! done < spins 2000000000 {
        ? ( virtq_has_used . d q ) {
            ?? ( virtq_get_used . d q ) {
                T head → {
                    : i _f ( virtq_free_chain . d q head )
                    = done T
                }
                F → { = spins + spins 1 }
            }
        } { = spins + spins 1 }
    }
    ( virtio_isr_ack . d base ( virtio_isr . d base ) )
    ? ! done { ^ F } {}
    ^ == # i ?? ( vec_get [u] . d st 0 ) { T x → x F → # u 255 } 0
}

@ vblk_read * VirtioBlk d i lba s buf i nsec → b {
    ? ! ( vblk_ready d ) { ^ F } {}
    ? <= nsec 0 { ^ F } {}
    ? > + lba nsec . d capacity { ^ F } {}
    ^ ( __request d ( vblk_type_in ) lba buf * nsec ( vblk_sector ) T )
}

@ vblk_write * VirtioBlk d i lba s buf i nsec → b {
    ? ! ( vblk_ready d ) { ^ F } {}
    ? . d readonly { ^ F } {}
    ? <= nsec 0 { ^ F } {}
    ? > + lba nsec . d capacity { ^ F } {}
    ^ ( __request d ( vblk_type_out ) lba buf * nsec ( vblk_sector ) F )
}

// A device that never negotiated FLUSH has no volatile cache to flush,
// so success is the truthful answer — not a refusal, and not a request
// the device would reject as unsupported.
@ vblk_flush * VirtioBlk d → b {
    ? ! ( vblk_ready d ) { ^ F } {}
    ? . d readonly { ^ T } {}
    ? ! . d flush_ok { ^ T } {}
    ^ ( __request d ( vblk_type_flush ) 0 # s 0 0 F )
}

@ vblk_close * VirtioBlk d → v {
    ? == # i d 0 { ^ } {}
    ( virtio_reset . d base )
    ( vec_free [u] . d hdr )
    ( vec_free [u] . d st )
    ( virtq_free . d q )
    ( nurl_free # s d )
}
