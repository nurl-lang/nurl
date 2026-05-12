// group_d_enum_payload.nu — named struct type as enum payload
//
// Expected output:
//   0
//   1

// Struct declared before enum so it's in syms when enum is parsed
: Pair { i x  i y }

// 'Full Pair' means variant Full with payload type Pair.
// Pair is known in syms → treated as payload type, NOT as a third variant.
: | Wrapped { Empty  Full Pair }

@ main → v {
  ( nurl_print_int Empty )   // 0
  ( nurl_print_int Full )    // 1  (would fail if Full were consumed as payload)
}
