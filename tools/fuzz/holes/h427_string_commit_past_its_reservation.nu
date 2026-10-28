// H427: `( string_commit s 4096 )` on a two-byte String: the length grew
// by any count and a NUL went 4096 bytes past the buffer. string_commit is
// the second half of string_reserve_at, whose raw cursor only unsafe code
// can take, but it was callable alone.
// Closed: string_commit is `raw` (requires the bytes it commits to have
// been reserved and written).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `ab` )
    ( string_commit s 4096 )
    ^ 0
}
