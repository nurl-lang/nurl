// pub_visibility.nu — exercises grammar v2.0 visibility control.
//
// The imported helper marks `pub_greet` and `pub_calls_priv` public;
// `__priv_greet` is unmarked and therefore private to the helper's
// own file. This file calls only the public surface, which must
// succeed. A separate negative case lives in
// `should_fail_pub_visibility_neg.nu` and is expected to COMPILE FAIL.

$ `compiler/tests/should_fail_pub_helper.nu`

@ main → i {
    ( pub_greet )  // direct pub call — OK
    ( pub_calls_priv )  // pub fn delegates internally to priv — OK
    ^ 0
}
