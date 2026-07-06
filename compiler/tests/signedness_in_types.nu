// A1 regression: signedness lives IN the type representation — the
// internal types u8/u16/u32/u64 stay distinct from i8..i64 end to end
// (bindings, struct fields, enum payloads, generic monomorphs, joins),
// with no `__last_unsigned__` flag side-channel to go stale. Each case
// below was either a latent miscompile under the flag machinery or
// depended on a hand-placed flag write.

// Case 1 (latent before A1): casting a struct to an integer reads
// field 0 and normalises it to i64 — an UNSIGNED narrow field 0 must
// zero-extend. The flag-era code hardcoded sext, so a high-bit byte
// (0xC8 = 200) came out negative.
: Wrap { u b i pad }

// Case 2: a u64 enum payload must round-trip through the i64 payload
// slot unchanged, including values above the signed max, and the match
// binding must keep unsigned semantics (udiv, not sdiv).
: | Carrier { Box u64 }

// Case 3: a generic over `* T` instantiated at `[ u64 ]` loads its
// element as u64 (the raw type rides the monomorph) and divides
// unsigned inside the generic body.
@ first_half [T] * T p → T {
    : T x . p 0
    ^ / x # T 2
}

@ main → i {
    // Case 1: field-0 cast zero-extends an unsigned byte.
    : Wrap w @ Wrap { # u 200 1 }
    ( nurl_print ( nurl_str_int # i64 w ) ) ( nurl_print `\n` )

    // Case 2: u64 payload with the high bit set survives the enum slot
    // and divides unsigned in the arm.
    : u64 big # u64 0x8000000000000006
    : Carrier c @ Carrier { Box big }
    ?? c {
        Box v → { ( nurl_print ( nurl_str_int # i / v # u64 2 ) ) ( nurl_print `\n` ) }
    }

    // Case 3: *u64 element with the high bit set halves unsigned.
    : s cell ( nurl_alloc 8 )
    ( nurl_poke cell 0 # i # u64 0x800000000000000A )
    : *u64 p # *u64 cell
    ( nurl_print ( nurl_str_int # i ( first_half [u64] p ) ) ) ( nurl_print `\n` )

    // Case 4: a `?`-join of an unsigned arm and a literal arm keeps the
    // unsigned spelling, so the enclosing division is udiv.
    : u64 uv # u64 0x8000000000000004
    : i pick 1
    ( nurl_print ( nurl_str_int # i / ? == pick 1 uv # u64 0 # u64 4 ) ) ( nurl_print `\n` )

    // Case 5: a `??`-match yielding a u64 from one arm and a cast
    // literal from another keeps unsigned semantics through the phi.
    : i sel 0
    : u64 mres ?? sel {
        0 → uv
        _ → # u64 8
    }
    ( nurl_print ( nurl_str_int # i / mres # u64 4 ) ) ( nurl_print `\n` )
    ^ 0
}
