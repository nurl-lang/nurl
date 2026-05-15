// should_fail_pub_const_neg.nu — negative test for grammar v2.0+
// global-constant visibility. `PRIV_CONST` is declared without `pub`
// in should_fail_pub_type_helper.nu (strict-mode is on). The use site
// in `+ PRIV_CONST 1` must fail to compile.

$ `compiler/tests/should_fail_pub_type_helper.nu`

@ main → i {
    ^ + PRIV_CONST 1   // FAIL — private global constant
}
