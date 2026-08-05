// stdlib/hal/virtio.nu — the virtio-mmio transport, as pure logic.
//
// `hal/virtq.nu` owns the split-ring: descriptors, avail, used, and
// the bookkeeping around them. This file owns the other half of the
// contract — the register window a virtio-mmio device presents, and
// the handshake that turns "there is a device here" into "the queues
// are live". Between them there is nothing device-specific: net, block
// and console differ in their config space and their queue count, not
// in any of this.
//
// PURE. Every access goes through `hal/mmio.nu`'s volatile load/store
// against an address the caller supplies, which makes the whole thing
// testable on the host by pointing `base` at an ordinary buffer and
// letting the test play the device. No mock interface, no injected
// function pointers: the device IS its register window, and a buffer
// is a register window that does not move on its own.
//
// ── modern only, on purpose ──────────────────────────────────────
//
// Version 2 (VIRTIO_F_VERSION_1) and nothing else. The plan's B5 note
// is precise about why "features to zero" is the wrong instinct: zero
// deselects VERSION_1 itself and makes us a LEGACY driver — 10-byte
// net header, PFN-based queue registers, guest-endian fields — and
// virtio-mmio version 2 requires VERSION_1 anyway. So the rule is
// "accept exactly VIRTIO_F_VERSION_1, reject every device-specific
// bit", which yields the modern queue layout, a fixed 12-byte
// virtio_net_hdr, no checksum offload and no MRG_RXBUF. Every checksum
// is then computed by the pure stack in `net/`, which is what that
// stack was built to do.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/hal/mmio.nu`

// ── the register window (spec §4.2.2) ────────────────────────────

@ vio_reg_magic → i { ^ 0 }

@ vio_reg_version → i { ^ 4 }

@ vio_reg_device_id → i { ^ 8 }

@ vio_reg_vendor_id → i { ^ 12 }

@ vio_reg_device_features → i { ^ 16 }

@ vio_reg_device_features_sel → i { ^ 20 }

@ vio_reg_driver_features → i { ^ 32 }

@ vio_reg_driver_features_sel → i { ^ 36 }

@ vio_reg_queue_sel → i { ^ 48 }

@ vio_reg_queue_num_max → i { ^ 52 }

@ vio_reg_queue_num → i { ^ 56 }

@ vio_reg_queue_ready → i { ^ 68 }

@ vio_reg_queue_notify → i { ^ 80 }

@ vio_reg_interrupt_status → i { ^ 96 }

@ vio_reg_interrupt_ack → i { ^ 100 }

@ vio_reg_status → i { ^ 112 }

@ vio_reg_queue_desc_low → i { ^ 128 }

@ vio_reg_queue_desc_high → i { ^ 132 }

@ vio_reg_queue_driver_low → i { ^ 144 }

@ vio_reg_queue_driver_high → i { ^ 148 }

@ vio_reg_queue_device_low → i { ^ 160 }

@ vio_reg_queue_device_high → i { ^ 164 }

@ vio_reg_config_generation → i { ^ 252 }

@ vio_reg_config → i { ^ 256 }

// "virt", little-endian.
@ vio_magic_value → i { ^ 1953655158 }

// ── status bits (spec §2.1) ──────────────────────────────────────

@ vio_status_acknowledge → i { ^ 1 }

@ vio_status_driver → i { ^ 2 }

@ vio_status_driver_ok → i { ^ 4 }

@ vio_status_features_ok → i { ^ 8 }

@ vio_status_needs_reset → i { ^ 64 }

@ vio_status_failed → i { ^ 128 }

// Feature bit 32. It lives in the upper word, which is why the
// features registers are selected a word at a time.
@ vio_f_version_1_word → i { ^ 1 }

@ vio_f_version_1_bit → i { ^ 1 }

// ── device ids we know by name ───────────────────────────────────

@ vio_id_net → i { ^ 1 }

@ vio_id_block → i { ^ 2 }

@ vio_id_console → i { ^ 3 }

@ vio_id_rng → i { ^ 4 }

// ── probe ────────────────────────────────────────────────────────

@ __rd i base i off → i { ^ ( mmio_read32 + base off ) }

@ __wr i base i off i val → v { ( mmio_write32 + base off # i32 val ) }

// What is at `base`? 0 means "nothing" — either no device (device_id
// 0, which the spec uses for an empty slot) or something this driver
// will not talk to. A wrong magic or a legacy version is reported as
// absent rather than half-driven: a legacy device needs a different
// queue layout and a different net header, and pretending otherwise
// produces a device that accepts descriptors and delivers nothing.
@ virtio_probe i base → i {
    ? != ( __rd base ( vio_reg_magic ) ) ( vio_magic_value ) { ^ 0 } {}
    ? != ( __rd base ( vio_reg_version ) ) 2 { ^ 0 } {}
    ^ ( __rd base ( vio_reg_device_id ) )
}

@ virtio_vendor i base → i { ^ ( __rd base ( vio_reg_vendor_id ) ) }

@ virtio_status i base → i { ^ ( __rd base ( vio_reg_status ) ) }

@ virtio_set_status i base i bits → v {
    ( __wr base ( vio_reg_status ) | ( __rd base ( vio_reg_status ) ) bits )
}

// A write of 0 to Status is the reset, and the spec requires waiting
// for the device to answer 0 back before touching anything else.
@ virtio_reset i base → v {
    ( __wr base ( vio_reg_status ) 0 )
    : ~ i spins 0
    ~ && != ( __rd base ( vio_reg_status ) ) 0 < spins 1000000 {
        = spins + spins 1
    }
}

// The device's feature word `sel` (0 = bits 0-31, 1 = bits 32-63).
@ virtio_device_features i base i sel → i {
    ( __wr base ( vio_reg_device_features_sel ) sel )
    ^ ( __rd base ( vio_reg_device_features ) )
}

@ virtio_set_driver_features i base i sel i bits → v {
    ( __wr base ( vio_reg_driver_features_sel ) sel )
    ( __wr base ( vio_reg_driver_features ) bits )
}

// The handshake, up to but not including DRIVER_OK: reset,
// ACKNOWLEDGE, DRIVER, features, FEATURES_OK, and the re-read that
// confirms the device accepted them.
//
// `want_lo` is the device-specific bits this driver is willing to take
// from word 0; word 1 is always exactly VIRTIO_F_VERSION_1. Returns T
// on success; on failure the device is left with FAILED set, because a
// device the driver gave up on must not be left looking half-ready to
// whatever runs next.
@ virtio_init i base i want_lo → b {
    ( virtio_reset base )
    ( virtio_set_status base ( vio_status_acknowledge ) )
    ( virtio_set_status base ( vio_status_driver ) )

    : i dev_hi ( virtio_device_features base 1 )
    ? == 0 & dev_hi ( vio_f_version_1_bit ) {
        // No VERSION_1 means a legacy device behind a version-2
        // register window — refuse rather than negotiate down.
        ( virtio_set_status base ( vio_status_failed ) )
        ^ F
    } {}
    : i dev_lo ( virtio_device_features base 0 )

    ( virtio_set_driver_features base 0 & dev_lo want_lo )
    ( virtio_set_driver_features base 1 ( vio_f_version_1_bit ) )

    ( virtio_set_status base ( vio_status_features_ok ) )
    ? == 0 & ( virtio_status base ) ( vio_status_features_ok ) {
        ( virtio_set_status base ( vio_status_failed ) )
        ^ F
    } {}
    ^ T
}

@ virtio_driver_ok i base → v {
    ( virtio_set_status base ( vio_status_driver_ok ) )
}

// ── queues ───────────────────────────────────────────────────────

@ virtio_queue_max i base i qidx → i {
    ( __wr base ( vio_reg_queue_sel ) qidx )
    ^ ( __rd base ( vio_reg_queue_num_max ) )
}

// Point queue `qidx` at a ring whose three parts live at the given
// PHYSICAL addresses and mark it ready.
//
// Physical, not virtual: the device is a bus master and does not go
// through our page tables. Under the identity map the two are equal,
// which is a property of this target and not a property of virtio —
// hence the parameter names saying which one they mean.
@ virtio_queue_setup i base i qidx i qsize i desc_phys i driver_phys i device_phys → b {
    ( __wr base ( vio_reg_queue_sel ) qidx )
    ? != 0 ( __rd base ( vio_reg_queue_ready ) ) { ^ F } {}
    : i maxq ( __rd base ( vio_reg_queue_num_max ) )
    ? == maxq 0 { ^ F } {}
    ? > qsize maxq { ^ F } {}
    ( __wr base ( vio_reg_queue_num ) qsize )
    ( __wr base ( vio_reg_queue_desc_low ) & desc_phys 4294967295 )
    ( __wr base ( vio_reg_queue_desc_high ) & >> desc_phys 32 4294967295 )
    ( __wr base ( vio_reg_queue_driver_low ) & driver_phys 4294967295 )
    ( __wr base ( vio_reg_queue_driver_high ) & >> driver_phys 32 4294967295 )
    ( __wr base ( vio_reg_queue_device_low ) & device_phys 4294967295 )
    ( __wr base ( vio_reg_queue_device_high ) & >> device_phys 32 4294967295 )
    ( __wr base ( vio_reg_queue_ready ) 1 )
    ^ T
}

@ virtio_notify i base i qidx → v { ( __wr base ( vio_reg_queue_notify ) qidx ) }

@ virtio_isr i base → i { ^ ( __rd base ( vio_reg_interrupt_status ) ) }

@ virtio_isr_ack i base i bits → v { ( __wr base ( vio_reg_interrupt_ack ) bits ) }

// Device configuration space, one byte at a time. The generation
// counter is how a multi-byte field is read without tearing: read it,
// read the field, read it again, and repeat if it changed.
@ virtio_config_u8 i base i off → i {
    ^ & ( __rd base + ( vio_reg_config ) & off ~ 3 ) 255
}

@ virtio_config_generation i base → i {
    ^ ( __rd base ( vio_reg_config_generation ) )
}

// ── discovery from the kernel command line ───────────────────────
//
// With `acpi=off` QEMU microvm publishes its virtio-mmio devices as
//
//     virtio_mmio.device=512@0xfeb00000:12
//                        size@base:irq
//
// on the kernel command line rather than in an ACPI table (plan B0).
// Parsing that beats writing an AML interpreter by a wide margin, and
// Firecracker uses the same convention, so this one path carries
// through to the demos.
//
// `size` accepts the K/M suffixes Linux writes. The IRQ is parsed and
// reported even though v1 polls every queue: a driver that discards it
// cannot later become interrupt-driven without changing its discovery.

: VioMmioDev {
    i base
    i size
    i irq
    b valid
}

@ __digit i c → i {
    ? && >= c 48 <= c 57 { ^ - c 48 } {}
    ? && >= c 97 <= c 102 { ^ - c 87 } {}
    ? && >= c 65 <= c 70 { ^ - c 55 } {}
    ^ -1
}

// Read a number at `off`, decimal or 0x-hex, stopping at the first
// character that is not a digit. Returns the value; `end` is where it
// stopped, via the caller's own scan.
@ __num s text i off i len → i {
    : ~ i k off
    : ~ i base 10
    ? && < + k 1 len && == ( nurl_str_get text k ) 48
    || == ( nurl_str_get text + k 1 ) 120 == ( nurl_str_get text + k 1 ) 88 {
        = base 16
        = k + k 2
    } {}
    : ~ i v 0
    ~ < k len {
        : i d ( __digit ( nurl_str_get text k ) )
        ? || < d 0 >= d base { = k len } {
            = v + * v base d
            = k + k 1
        }
    }
    ^ v
}

@ __num_end s text i off i len → i {
    : ~ i k off
    ? && < + k 1 len && == ( nurl_str_get text k ) 48
    || == ( nurl_str_get text + k 1 ) 120 == ( nurl_str_get text + k 1 ) 88 {
        = k + k 2
    } {}
    : ~ i base ? > k off 16 10
    : ~ b more T
    ~ && more < k len {
        : i d ( __digit ( nurl_str_get text k ) )
        ? || < d 0 >= d base { = more F } { = k + k 1 }
    }
    ^ k
}

// The `idx`-th `virtio_mmio.device=` entry on the command line, or an
// invalid device when there are fewer than that.
@ virtio_mmio_from_cmdline s cmdline i idx → VioMmioDev {
    : i n ( nurl_str_len cmdline )
    : s key `virtio_mmio.device=`
    : i klen ( nurl_str_len key )
    : ~ i seen 0
    : ~ i k 0
    ~ <= k - n klen {
        : ~ b match T
        : ~ i j 0
        ~ && match < j klen {
            ? != ( nurl_str_get cmdline + k j ) ( nurl_str_get key j ) { = match F } {}
            = j + j 1
        }
        ? match {
            ? == seen idx {
                : i p + k klen
                : i size_v ( __num cmdline p n )
                : i after ( __num_end cmdline p n )
                : ~ i size size_v
                : ~ i q after
                ? < q n {
                    : i c ( nurl_str_get cmdline q )
                    ? || == c 75 == c 107 { = size * size 1024 = q + q 1 } {}
                    ? || == c 77 == c 109 { = size * size 1048576 = q + q 1 } {}
                } {}
                // '@' then the base, ':' then the irq.
                ? >= q n { ^ @ VioMmioDev { 0 0 0 F } } {}
                ? != ( nurl_str_get cmdline q ) 64 { ^ @ VioMmioDev { 0 0 0 F } } {}
                : i bstart + q 1
                : i base_v ( __num cmdline bstart n )
                : i bend ( __num_end cmdline bstart n )
                : ~ i irq 0
                ? && < bend n == ( nurl_str_get cmdline bend ) 58 {
                    = irq ( __num cmdline + bend 1 n )
                } {}
                ^ @ VioMmioDev { base_v size irq T }
            } {}
            = seen + seen 1
            = k + k klen
        } { = k + k 1 }
    }
    ^ @ VioMmioDev { 0 0 0 F }
}

// How many entries the command line carries.
@ virtio_mmio_count s cmdline → i {
    : ~ i n 0
    ~ . ( virtio_mmio_from_cmdline cmdline n ) valid { = n + n 1 }
    ^ n
}
