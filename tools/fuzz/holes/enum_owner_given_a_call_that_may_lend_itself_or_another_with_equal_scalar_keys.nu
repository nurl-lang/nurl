// enum_owner_given_a_call_that_may_lend_itself_or_another_with_equal_scalar_keys: agora #450 — `: | E { A i String N }`, both values `A 7 …`, `= o ( epick o other 1 )`
// Closed: an enum's identity key is its ACTIVE variant's first payload slot that owns a heap buffer (null for a variant that owns nothing), not its first payload slot, which may hold a number another value holds too (mem_enum_variant_key; agora #450).
// main: heap-use-after-free (base 8452c536 too).
// map: §7.6 | A2 | runs-clean | - | agora #450: `: | E { A i String N }`, both values `A 7 …`, `= o ( epick o other 1 )`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

: | E { A i String N }

@ epick E a E b i k → E { ? == k 0 { ^ a } {} ^ b }

@ main → i {
    : ~ E o @ E { A 7 ( make ) }
    : E other @ E { A 7 ( make2 ) }
    = o ( epick o other 1 )
    ?? o { A n s → { ( nurl_println ( string_data s ) ) } N → {} }
    ?? other { A n s → { ( nurl_println ( string_data s ) ) } N → {} }
    ^ 0
}
