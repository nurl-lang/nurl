// trusted_by_path_substring: any source whose path contains `/stdlib/` is compiled as the trusted standard library.
// Closed: only a file inside the real standard-library tree — where `stdlib/` imports resolve — is trusted (bck_trusted_file).
// bck_trusted_file (compiler/nurlc.nu) trusts a path that starts with `stdlib/` or contains `/stdlib/`
// (and not `/deps/`), so every safe-code check is off in any directory named stdlib — this one too:
// any REJECTED tools/fuzz/holes/h*.nu (h100, say) compiles when copied here. The program is
// mem_forget_owned_vec.nu (h155): rejected here as anywhere else.
// LSan: detected memory leaks — the Vec's control block (24 bytes) and its element buffer (32 bytes).
// map: §6.4 | B | rejected | h178 | any path containing /stdlib/ compiled as trusted stdlib, checks off
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ( mem_forget v )
    ( nurl_println `ran` )
    ^ 0
}
