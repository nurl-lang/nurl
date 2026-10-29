// H483: `( fatfs_write h src 8 9223372036854775800 )` wrote far past the
// 16-byte source: the range test `off + n > len` wrapped negative and
// passed.
// Closed: the test is `n > len - off` with off in [0, len]; the block
// layer's own range tests (`__blk_ptr`, `__blk_range_ok`) no longer add
// either.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/hal/blockdev.nu`
$ `stdlib/fs/blkdev_file.nu`
$ `stdlib/fs/fat.nu`
$ `stdlib/fs/fatfs.nu`
$ `stdlib/fs/fatfmt.nu`

@ main → i {
    : b c ( blkfile_create `/tmp/nurl_h483_fat.img` 8192 )
    : b f ( fat_format `PROBE` )
    : b m ( fat_mount T )
    : i h ( fatfs_open `/a.bin` | | ( fo_rdwr ) ( fo_creat ) ( fo_trunc ) )
    : ( Vec u ) src ( vec_zeroed [u] 16 )
    : i w ( fatfs_write h src 8 9223372036854775800 )
    ( nurl_println_int w )
    ^ 0
}
