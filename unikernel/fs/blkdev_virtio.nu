// unikernel/fs/blkdev_virtio.nu — the block device is a virtio-blk
// device.
//
// The guest's half of the pair whose other half is `blkdev_none.nu`:
// four functions, chosen by the build, so the filesystem above has one
// seam rather than a conditional. Everything real is in
// `drivers/virtioblk.nu`; this file is the adapter that turns a driver
// object into the four calls `stdlib/hal/blockdev.nu` declares.
//
// The device is opened ON FIRST USE and the attempt is made once. A
// machine with no disk asks the command line once, gets no device, and
// answers "zero sectors" for ever after — rather than re-probing MMIO
// registers on every read of a filesystem that is not there.
$ `stdlib/core/vec.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtq.nu`
$ `stdlib/hal/virtio.nu`
$ `stdlib/hal/blockdev.nu`
$ `unikernel/drivers/virtioblk.nu`

: ~ i g_blk 0
: ~ b g_probed F

@ __blkdev → *VirtioBlk {
    ? != g_blk 0 { ^ # *VirtioBlk g_blk } {}
    ? g_probed { ^ # *VirtioBlk 0 } {}
    = g_probed T
    : *VirtioBlk d ( vblk_open 16 )
    ? ! ( vblk_ready d ) { ^ # *VirtioBlk 0 } {}
    = g_blk # i d
    ^ d
}

@ nurl_blk_sector_count → i {
    : *VirtioBlk d ( __blkdev )
    ? == # i d 0 { ^ 0 } {}
    ^ ( vblk_capacity d )
}

@ nurl_blk_read i lba s buf i nsec → i {
    : *VirtioBlk d ( __blkdev )
    ? == # i d 0 { ^ - 0 1 } {}
    ^ ? ( vblk_read d lba buf nsec ) nsec - 0 1
}

@ nurl_blk_write i lba s buf i nsec → i {
    : *VirtioBlk d ( __blkdev )
    ? == # i d 0 { ^ - 0 1 } {}
    ^ ? ( vblk_write d lba buf nsec ) nsec - 0 1
}

@ nurl_blk_flush → i {
    : *VirtioBlk d ( __blkdev )
    ? == # i d 0 { ^ - 0 1 } {}
    ^ ? ( vblk_flush d ) 0 - 0 1
}

// Whether the DEVICE refuses writes, which is a different question from
// whether the volume was mounted read-only: `-drive …,readonly=on` is
// the hypervisor's decision and `disk=ro` is ours.
@ nurl_blk_device_readonly → i {
    : *VirtioBlk d ( __blkdev )
    ? == # i d 0 { ^ 1 } {}
    ^ ? ( vblk_readonly d ) 1 0
}
