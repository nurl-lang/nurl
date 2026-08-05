// unikernel/demos/devices.nu — what did the hypervisor give us?
//
// The first program that talks to hardware: it reads the kernel
// command line, walks the `virtio_mmio.device=` entries QEMU microvm
// publishes there (acpi=off, so there is no ACPI table to walk), and
// drives each device far enough to prove the transport works —
// through the feature handshake, which is where a legacy device or a
// disagreement about VERSION_1 shows up.
//
// It stops before DRIVER_OK: a device is not ready until its queues
// are, and queues are the next piece of work. What this establishes is
// that discovery, the register window and the handshake are right on
// the real machine and not only against the buffer in virtio_mmio.nu.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtio.nu`

& `c` @ nurl_boot_cmdline → s

@ name_of i id → s {
    ? == id ( vio_id_net ) { ^ `net` } {}
    ? == id ( vio_id_block ) { ^ `block` } {}
    ? == id ( vio_id_console ) { ^ `console` } {}
    ? == id ( vio_id_rng ) { ^ `rng` } {}
    ^ `other`
}

@ main → i {
    : s cl ( nurl_boot_cmdline )
    : i n ( virtio_mmio_count cl )
    ( nurl_print `cmdline devices: ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )

    : ~ i found 0
    : ~ i k 0
    ~ < k n {
        : VioMmioDev d ( virtio_mmio_from_cmdline cl k )
        : i id ( virtio_probe . d base )
        ? != id 0 {
            = found + found 1
            ( nurl_print `device ` ) ( nurl_print ( nurl_str_int k ) )
            ( nurl_print `: id=` ) ( nurl_print ( nurl_str_int id ) )
            ( nurl_print ` (` ) ( nurl_print ( name_of id ) ) ( nurl_print `)` )
            // The base address and the IRQ are the hypervisor's to
            // choose and its version's to change, so what is printed
            // is that they are THERE — a golden that pins QEMU's
            // current layout would fail on the next QEMU.
            ( nurl_print ` irq=` ) ( nurl_print ? > . d irq 0 `yes` `no` )
            ( nurl_print ` queues=` ) ( nurl_print ? > ( virtio_queue_max . d base 0 ) 0 `yes` `no` )
            ( nurl_print `\n` )
            // The handshake, exactly VERSION_1 and no device-specific
            // bits: this driver has no use for any of them yet, and
            // taking a feature it does not implement is how a device
            // starts delivering a format nobody parses.
            : b ok ( virtio_init . d base 0 )
            ( nurl_print `  features negotiated: ` )
            ( nurl_print ? ok `yes` `no` )
            ( nurl_print `\n` )
        } {}
        = k + k 1
    }
    ( nurl_print `probed ok: ` ) ( nurl_print ( nurl_str_int found ) ) ( nurl_print `\n` )
    ^ ? > found 0 0 1
}
