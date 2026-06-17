// should_fail_store_void.nu — the void/unit value (a bare type keyword `v`)
// cannot initialise a binding (`: i y v`). Rejected at the source instead of
// emitting `store i64 void`.
@ main → i { : i y v  ^ 0 }
