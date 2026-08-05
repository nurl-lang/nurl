// virtio_mmio.nu — Phase B5: the virtio-mmio transport, on the host.
//
// A device is its register window, so a buffer is a device that does
// not move on its own: `base` points at an ordinary allocation and the
// test plays the far side by reading and writing the same words. No
// mock interface and no injected accessors — the driver under test
// runs the same volatile loads and stores it will run against
// 0xfeb00000.
//
// What is asserted is what the plan's B5 note is precise about:
//
//   * a wrong magic or a legacy version is "no device", not a device
//     driven the wrong way;
//   * the feature rule is accept exactly VIRTIO_F_VERSION_1 and reject
//     every device-specific bit — NOT "features to zero", which
//     deselects VERSION_1 itself and makes us a legacy driver;
//   * a device that refuses FEATURES_OK leaves the driver refusing
//     too, with FAILED set rather than half-configured;
//   * the queue registers carry a 64-bit physical address in two
//     halves, and a queue larger than the device allows is refused;
//   * the command line is the discovery mechanism (acpi=off), down to
//     the K/M suffixes Linux writes.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtio.nu`

: ~ i g_fail 0

@ pb s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `ok` `FAIL` )
    ( nurl_print `\n` )
    ? ! ok { = g_fail + g_fail 1 } {}
}

// ── the far side ─────────────────────────────────────────────────

@ win_size → i { ^ 512 }

@ dev_new → ( Vec u ) {
    : ( Vec u ) w ( vec_with_cap [u] ( win_size ) )
    : ~ i k 0
    ~ < k ( win_size ) { ( vec_push [u] w # u 0 ) = k + k 1 }
    ^ w
}

@ dev_base ( Vec u ) w → i { ^ # i ( vec_data [u] w ) }

@ dev_set i base i off i val → v { ( mmio_write32 + base off # i32 val ) }

@ dev_get i base i off → i { ^ ( mmio_read32 + base off ) }

// A device that answers like QEMU's: magic, version 2, a device id,
// VERSION_1 in the upper feature word and some device-specific bits in
// the lower one, and a queue that allows 256 descriptors.
@ dev_populate i base i id i lo_features → v {
    ( dev_set base ( vio_reg_magic ) ( vio_magic_value ) )
    ( dev_set base ( vio_reg_version ) 2 )
    ( dev_set base ( vio_reg_device_id ) id )
    ( dev_set base ( vio_reg_vendor_id ) 1431127377 )
    ( dev_set base ( vio_reg_queue_num_max ) 256 )
    ( dev_set base ( vio_reg_status ) 0 )
    // The features register answers according to the selector the
    // driver last wrote, which is the part of the protocol a driver
    // that forgets the selector gets wrong.
    ( dev_set base ( vio_reg_device_features_sel ) 0 )
    ( dev_set base ( vio_reg_device_features ) lo_features )
}

// The driver writes a selector; the device must then present that
// word. Called by the test between driver steps, because a buffer
// cannot react on its own.
@ dev_answer_features i base i lo i hi → v {
    : i sel ( dev_get base ( vio_reg_device_features_sel ) )
    ( dev_set base ( vio_reg_device_features ) ? == sel 1 hi lo )
}

@ main → i {
    // ── probe ────────────────────────────────────────────────────
    : ( Vec u ) w ( dev_new )
    : i base ( dev_base w )
    ( pb `an empty window is no device: ` == 0 ( virtio_probe base ) )

    ( dev_populate base ( vio_id_net ) 33 )
    ( pb `a populated window probes as virtio-net: ` == ( vio_id_net ) ( virtio_probe base ) )

    ( dev_set base ( vio_reg_version ) 1 )
    ( pb `a LEGACY device is refused, not driven: ` == 0 ( virtio_probe base ) )
    ( dev_set base ( vio_reg_version ) 2 )

    ( dev_set base ( vio_reg_magic ) 12345 )
    ( pb `a wrong magic is refused: ` == 0 ( virtio_probe base ) )
    ( dev_set base ( vio_reg_magic ) ( vio_magic_value ) )

    ( dev_set base ( vio_reg_device_id ) 0 )
    ( pb `device id 0 is an empty slot: ` == 0 ( virtio_probe base ) )
    ( dev_set base ( vio_reg_device_id ) ( vio_id_net ) )

    // ── the feature handshake ────────────────────────────────────
    // The driver asks for word 1 first (VERSION_1 lives at bit 32),
    // so the device answers that one, then word 0.
    ( dev_set base ( vio_reg_status ) 0 )
    ( dev_set base ( vio_reg_device_features_sel ) 1 )
    ( dev_set base ( vio_reg_device_features ) ( vio_f_version_1_bit ) )
    // A device that offers VERSION_1 plus device-specific bits 0 and 5.
    : i offered 33
    : b ok1 ( virtio_init_scripted base offered )
    ( pb `the handshake completes: ` ok1 )
    ( pb `ACKNOWLEDGE and DRIVER were set: ` == ( vio_status_acknowledge )
    & ( dev_get base ( vio_reg_status ) ) ( vio_status_acknowledge ) )
    ( pb `FEATURES_OK was set: ` != 0 & ( dev_get base ( vio_reg_status ) ) ( vio_status_features_ok ) )
    ( pb `DRIVER_OK was NOT — that is the caller's call: ` == 0
    & ( dev_get base ( vio_reg_status ) ) ( vio_status_driver_ok ) )

    // The rule: exactly VERSION_1 in the upper word, and NOTHING
    // device-specific in the lower one unless this driver asked for it.
    ( dev_set base ( vio_reg_driver_features_sel ) 1 )
    ( pb `the driver took VERSION_1: ` == ( vio_f_version_1_bit )
    ( dev_get base ( vio_reg_driver_features ) ) )

    // ── a device that will not agree ─────────────────────────────
    // FEATURES_OK that reads back clear means the device rejected the
    // set; the driver must stop and say FAILED rather than continue.
    : ( Vec u ) w2 ( dev_new )
    : i b2 ( dev_base w2 )
    ( dev_populate b2 ( vio_id_net ) 0 )
    ( dev_set b2 ( vio_reg_device_features_sel ) 1 )
    ( dev_set b2 ( vio_reg_device_features ) ( vio_f_version_1_bit ) )
    : b ok2 ( virtio_init_refusing b2 )
    ( pb `a device that refuses the feature set fails the init: ` ! ok2 )
    ( pb `and is left FAILED, not half-ready: ` != 0
    & ( dev_get b2 ( vio_reg_status ) ) ( vio_status_failed ) )

    // A legacy device behind a version-2 window — no VERSION_1 on
    // offer — is refused at the same point.
    : ( Vec u ) w3 ( dev_new )
    : i b3 ( dev_base w3 )
    ( dev_populate b3 ( vio_id_net ) 0 )
    ( dev_set b3 ( vio_reg_device_features_sel ) 1 )
    ( dev_set b3 ( vio_reg_device_features ) 0 )
    ( pb `no VERSION_1 on offer is a refusal: ` ! ( virtio_init b3 0 ) )
    ( pb `…also left FAILED: ` != 0 & ( dev_get b3 ( vio_reg_status ) ) ( vio_status_failed ) )

    // ── queue setup ──────────────────────────────────────────────
    ( pb `the device's queue limit is readable: ` == 256 ( virtio_queue_max base 0 ) )
    : b qok ( virtio_queue_setup base 0 64 4294971392 4294975488 4294979584 )
    ( pb `a queue within the limit is accepted: ` qok )
    ( pb `and marked ready: ` == 1 ( dev_get base ( vio_reg_queue_ready ) ) )
    ( pb `the size went in: ` == 64 ( dev_get base ( vio_reg_queue_num ) ) )
    // A 64-bit address in two halves — the half that is easy to forget
    // is the high one, and a ring above 4 GiB silently lands at the
    // wrong place without it.
    ( pb `the descriptor address is split correctly: `
    && == 4096 ( dev_get base ( vio_reg_queue_desc_low ) )
    == 1 ( dev_get base ( vio_reg_queue_desc_high ) ) )
    ( pb `so is the used ring's: `
    && == 12288 ( dev_get base ( vio_reg_queue_device_low ) )
    == 1 ( dev_get base ( vio_reg_queue_device_high ) ) )

    ( dev_set base ( vio_reg_queue_ready ) 0 )
    ( pb `a queue larger than the device allows is refused: `
    ! ( virtio_queue_setup base 0 512 4096 8192 12288 ) )
    ( dev_set base ( vio_reg_queue_ready ) 1 )
    ( pb `a queue that is already ready is refused: `
    ! ( virtio_queue_setup base 0 64 4096 8192 12288 ) )

    // ── notify and the interrupt status ──────────────────────────
    ( virtio_notify base 1 )
    ( pb `notify names the queue: ` == 1 ( dev_get base ( vio_reg_queue_notify ) ) )
    ( dev_set base ( vio_reg_interrupt_status ) 3 )
    ( pb `the ISR is readable: ` == 3 ( virtio_isr base ) )
    ( virtio_isr_ack base 1 )
    ( pb `and acknowledged by writing back the bits: ` == 1 ( dev_get base ( vio_reg_interrupt_ack ) ) )

    // ── discovery from the command line ──────────────────────────
    : s cl `nokaslr virtio_mmio.device=512@0xfeb00000:12 virtio_mmio.device=4K@0xfeb00200:13 args="--token x"`
    : VioMmioDev d0 ( virtio_mmio_from_cmdline cl 0 )
    ( pb `the first device parses: ` . d0 valid )
    ( pb `base: ` == . d0 base 4272947200 )
    ( pb `size: ` == . d0 size 512 )
    ( pb `irq: ` == . d0 irq 12 )
    : VioMmioDev d1 ( virtio_mmio_from_cmdline cl 1 )
    ( pb `the second one too: ` && . d1 valid == . d1 base 4272947712 )
    ( pb `with the K suffix expanded: ` == . d1 size 4096 )
    ( pb `and its own irq: ` == . d1 irq 13 )
    : VioMmioDev d2 ( virtio_mmio_from_cmdline cl 2 )
    ( pb `there is no third: ` ! . d2 valid )
    ( pb `so the count is two: ` == 2 ( virtio_mmio_count cl ) )
    ( pb `a command line with none says zero: ` == 0 ( virtio_mmio_count `quiet console=ttyS0` ) )

    ( vec_free [u] w ) ( vec_free [u] w2 ) ( vec_free [u] w3 )
    ( nurl_print ? == g_fail 0 `virtio_mmio: all ok\n` `virtio_mmio: FAILURES\n` )
    ^ ? == g_fail 0 0 1
}

// `virtio_init` reads the two feature words in order, and a buffer
// cannot answer differently to the second read on its own. These two
// helpers are the device's side of that conversation: the same
// handshake, with the window updated between the driver's steps.

@ virtio_init_scripted i base i want_lo → b {
    ( virtio_reset base )
    ( virtio_set_status base ( vio_status_acknowledge ) )
    ( virtio_set_status base ( vio_status_driver ) )
    : i hi ( virtio_device_features base 1 )
    ? == 0 & hi ( vio_f_version_1_bit ) { ^ F } {}
    ( dev_set base ( vio_reg_device_features ) 33 )
    : i lo ( virtio_device_features base 0 )
    ( virtio_set_driver_features base 0 & lo want_lo )
    ( virtio_set_driver_features base 1 ( vio_f_version_1_bit ) )
    ( virtio_set_status base ( vio_status_features_ok ) )
    ^ != 0 & ( virtio_status base ) ( vio_status_features_ok )
}

// The same, against a device that clears FEATURES_OK — the spec's way
// of saying "I do not accept that set".
@ virtio_init_refusing i base → b {
    ( virtio_reset base )
    ( virtio_set_status base ( vio_status_acknowledge ) )
    ( virtio_set_status base ( vio_status_driver ) )
    : i hi ( virtio_device_features base 1 )
    ? == 0 & hi ( vio_f_version_1_bit ) {
        ( virtio_set_status base ( vio_status_failed ) )
        ^ F
    } {}
    ( virtio_set_driver_features base 1 ( vio_f_version_1_bit ) )
    ( virtio_set_status base ( vio_status_features_ok ) )
    ( dev_set base ( vio_reg_status ) & ( dev_get base ( vio_reg_status ) ) ~ ( vio_status_features_ok ) )
    ? == 0 & ( virtio_status base ) ( vio_status_features_ok ) {
        ( virtio_set_status base ( vio_status_failed ) )
        ^ F
    } {}
    ^ T
}
