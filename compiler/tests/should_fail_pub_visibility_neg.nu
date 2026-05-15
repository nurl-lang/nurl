// should_fail_pub_visibility_neg.nu — negative test for v2.0
// visibility. Calls `__priv_greet`, which is private to
// `should_fail_pub_helper.nu` (strict-mode applied because that file
// has at least one `pub` decl). The compile MUST fail; the snapshot
// captures `COMPILE FAIL` for this entry.

$ `compiler/tests/should_fail_pub_helper.nu`

@ main → i {
    ( __priv_greet )      // FAIL — private to the helper file
    ^ 0
}
