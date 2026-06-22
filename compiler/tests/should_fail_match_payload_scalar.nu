// should_fail_match_payload_scalar.nu — binding a payload while matching a
// non-aggregate scalar (`?? n { T a → … }` with n : i) used to emit an
// `extractvalue` on the scalar. Only enums / options / results carry payloads.
@ main → i { : i n 5 ^ ?? n { T a → a F → 0 } }
