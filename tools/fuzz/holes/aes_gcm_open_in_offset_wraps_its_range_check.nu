// aes_gcm_open_in_offset_wraps_its_range_check: `( aes_gcm_open_in key iv seq buf aad_at data_at end )` with
// `data_at` near 2^63: the check `data_at + 16 > end` wrapped and passed,
// and GCM ran over (and zeroed) memory 2^63 bytes past the buffer, with a
// hardware key or the software one. (`aes_gcm_seal_in` checks its offsets
// without arithmetic and was not affected.)
// Closed: the check is `end < 16 | end > len | data_at > end - 16`, which
// cannot wrap; the call returns F.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | runs-clean | h450 | `( aes_gcm_open_in key iv seq buf aad_at data_at end )` with `data_at` near 2^63: the check `data_at + 16 > end` wrapped and passed, and GCM ran over (and zeroed) memory 2^63 bytes past the…
$ `stdlib/core/vec.nu`
$ `stdlib/std/aes_gcm.nu`

@ main → i {
    : ( Vec u ) kb ( vec_zeroed [u] 16 )
    : AesGcmKey k ( _aes_gcm_key_sw kb )
    : ( Vec u ) iv ( vec_zeroed [u] 12 )
    : ( Vec u ) buf ( vec_zeroed [u] 64 )
    : b r ( aes_gcm_open_in k iv 0 buf 0 9223372036854775800 64 )
    ( nurl_println ? r `opened` `refused` )
    ^ 0
}
