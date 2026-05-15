// should_fail_pub_variant_neg.nu — negative test for v2.0+ enum-
// variant visibility. `PrivColor`'s variants (`Black`, `White`) are
// private because the enum itself wasn't marked pub in
// should_fail_pub_type_helper.nu (strict-mode is on). Using a variant
// from another file emits the "private global" diagnostic at the
// `# PrivColor Black` cast site.

$ `compiler/tests/should_fail_pub_type_helper.nu`

@ main → i {
    : PrivColor c # PrivColor Black   // FAIL — private enum variant
    ^ # i c
}
