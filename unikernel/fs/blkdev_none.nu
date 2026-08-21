// unikernel/fs/blkdev_none.nu — this machine has no disk.
//
// The other half of the pair whose first half is `blkdev_virtio.nu`,
// chosen by the build the same way `net/netdev_none.nu` is: a program
// linked against the filesystem on a machine with no block device gets
// these, and every layer above answers "there is no device" instead of
// probing one that is not there.
//
// Zero sectors is the whole contract. `blk_present` is false, `fat_mount`
// refuses, and the VFS in `boot/vfs.c` never asks a second question.
$ `stdlib/hal/blockdev.nu`

@ nurl_blk_sector_count → i { ^ 0 }

@ nurl_blk_read i lba s buf i nsec → i { ^ - 0 1 }

@ nurl_blk_write i lba s buf i nsec → i { ^ - 0 1 }

@ nurl_blk_flush → i { ^ - 0 1 }
