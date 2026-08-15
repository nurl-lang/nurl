// diag_payload_struct_into_number.nu — a struct/handle in a payload slot
// declared as a number.
//
// The pointer form was rejected in #901 and the user-enum form in #908.
// A `Vec` reaches the payload path as `%Vec__i64` — a NAMED struct, not
// a raw pointer — so it took the struct-handle branch, which folds the
// value to an i64 (inline-f0 or a heap box) and hands it to the slot.
// The `??` arm then reads that slot back as the declared type:
//
//     : ?i o @ ?i { T d }        // d is a ( Vec i )
//     ^ ?? o { T v → v  F → 0 }  // returned 192 — a heap address's low byte
//
// Same lie as #901, one branch over. Found by tools/metamorph, whose
// IR-validity invariant does NOT catch it: the module verifies fine, the
// VALUE is wrong.

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) d ( vec_new [i] )
    ( vec_push [i] d 7 )
    : ?i o @ ?i { T d }
    ^ ?? o { T v → v F → 0 }
}
