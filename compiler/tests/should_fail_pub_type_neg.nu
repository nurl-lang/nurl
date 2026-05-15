// should_fail_pub_type_neg.nu — negative test for grammar v2.0+
// type visibility. `PrivPoint` is declared without `pub` in
// should_fail_pub_type_helper.nu, which flipped strict-mode on (it
// has at least one pub decl). The use site at `: PrivPoint p ...`
// must fail to compile.

$ `compiler/tests/should_fail_pub_type_helper.nu`

@ main → i {
    : PrivPoint p @ PrivPoint { 1 2 }   // FAIL — private type
    ^ . p x
}
