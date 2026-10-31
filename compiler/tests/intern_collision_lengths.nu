// intern_collision_lengths.nu — two names of different lengths that the
// symbol tables hash alike (agora #304).
//
// `icco0q` (6 bytes) and `icl_aaaa2g_x` (12 bytes) have the same 31-bit
// __sym_hash_n, so nurlc's string interner meets the one's entry while it
// looks for the other. A probe used to compare 12 bytes of the 6-byte
// entry before it looked at that entry's end, reading past it (past its
// arena chunk when the entry was the chunk's last: a heap-buffer-overflow
// under the sanitized compiler). The stored length is now compared first.
// Each name must still be its own function, in either order of use.
//
// Expected output:
//   6
//   12
//   18

@ icco0q → i { ^ 6 }

@ icl_aaaa2g_x → i { ^ 12 }

@ main → i {
    ( nurl_println_int ( icco0q ) )
    ( nurl_println_int ( icl_aaaa2g_x ) )
    ( nurl_println_int + ( icl_aaaa2g_x ) ( icco0q ) )
    ^ 0
}
