// stdlib/std/bitset.nu — a fixed-size bit array over 64-bit limbs.
//
// A `Bitset` is created with a bit count and never resizes; bits outside
// [0, nbits) are rejected (set/clear/flip) or read as 0 (test), so the
// unused high bits of the last limb stay clear and `bitset_count` /
// `bitset_all` can treat every stored word at face value. Storage is a
// flat `nurl_zalloc` buffer of `ceil(nbits/64)` words, peeked/poked by
// word index. No element ownership — `bitset_free` is the whole story.
//
//   ( bitset_new      i nbits )          → Bitset
//   ( bitset_nbits    Bitset bs )        → i
//   ( bitset_words    Bitset bs )        → i   limb count
//   ( bitset_set      Bitset bs i bit )  → v
//   ( bitset_clear    Bitset bs i bit )  → v
//   ( bitset_flip     Bitset bs i bit )  → v
//   ( bitset_test     Bitset bs i bit )  → b
//   ( bitset_set_all  Bitset bs )        → v
//   ( bitset_clear_all Bitset bs )       → v
//   ( bitset_count    Bitset bs )        → i   set bits (popcount)
//   ( bitset_any      Bitset bs )        → b
//   ( bitset_all      Bitset bs )        → b
//   ( bitset_none     Bitset bs )        → b
//   ( bitset_and_with Bitset a Bitset b ) → v  a &= b   (over min limbs)
//   ( bitset_or_with  Bitset a Bitset b ) → v  a |= b
//   ( bitset_xor_with Bitset a Bitset b ) → v  a ^= b
//   ( bitset_clone    Bitset bs )        → Bitset
//   ( bitset_each_set Bitset bs ( @ v i ) f ) → v   set indices, ascending
//   ( bitset_free     Bitset bs )        → v
//
// NURL has no native XOR or NOT operator, so this module uses the
// identities  a^b = (a|b) - (a&b)  and  ~m = -1 - m  (two's complement),
// both exact and carry-free per bit.

: Bitset { s words i nbits i nwords }

@ bitset_new i nbits → Bitset {
    : i nb ? > nbits 0 nbits 0
    : i nw / + nb 63 64
    : s w ? > nw 0 ( nurl_zalloc * nw 8 ) # s 0
    ^ @ Bitset { w nb nw }
}

@ bitset_nbits Bitset bs → i { ^ . bs nbits }
@ bitset_words Bitset bs → i { ^ . bs nwords }

@ __bit_inrange Bitset bs i bit → b {
    ^ & >= bit 0 < bit . bs nbits
}

@ bitset_set Bitset bs i bit → v {
    ? ( __bit_inrange bs bit ) {
        : s w . bs words
        : i limb / bit 64
        : i mask << 1 % bit 64
        ( nurl_poke w limb | ( nurl_peek w limb ) mask )
    } {}
}

@ bitset_clear Bitset bs i bit → v {
    ? ( __bit_inrange bs bit ) {
        : s w . bs words
        : i limb / bit 64
        : i mask << 1 % bit 64
        ( nurl_poke w limb & ( nurl_peek w limb ) - -1 mask )   // &= ~mask
    } {}
}

@ bitset_flip Bitset bs i bit → v {
    ? ( __bit_inrange bs bit ) {
        : s w . bs words
        : i limb / bit 64
        : i mask << 1 % bit 64
        : i cur ( nurl_peek w limb )
        ( nurl_poke w limb - | cur mask & cur mask )            // ^= mask
    } {}
}

@ bitset_test Bitset bs i bit → b {
    ? ( __bit_inrange bs bit ) {} { ^ F }
    : s w . bs words
    : i limb / bit 64
    : i mask << 1 % bit 64
    ^ != & ( nurl_peek w limb ) mask 0
}

@ bitset_clear_all Bitset bs → v {
    : s w . bs words
    : ~ i k 0
    ~ < k . bs nwords { ( nurl_poke w k 0 ) = k + k 1 }
}

// Set every in-range bit; the unused high bits of the last limb are
// left clear so the count / all invariants hold.
@ bitset_set_all Bitset bs → v {
    : s w . bs words
    : i nw . bs nwords
    : i rem % . bs nbits 64
    : ~ i k 0
    ~ < k nw {
        ? & == k - nw 1 != rem 0
        { ( nurl_poke w k - << 1 rem 1 ) }   // last partial word: low `rem` bits
        { ( nurl_poke w k -1 ) }             // full word: all ones
        = k + k 1
    }
}

// Kernighan popcount of a 64-bit word (works on the sign bit too — the
// loop clears the lowest set bit each step and ends at zero).
@ __popcount64 i x → i {
    : ~ i v x
    : ~ i c 0
    ~ != v 0 { = v & v - v 1 = c + c 1 }
    ^ c
}

@ bitset_count Bitset bs → i {
    : s w . bs words
    : ~ i total 0
    : ~ i k 0
    ~ < k . bs nwords { = total + total ( __popcount64 ( nurl_peek w k ) ) = k + k 1 }
    ^ total
}

@ bitset_any Bitset bs → b {
    : s w . bs words
    : ~ i k 0
    ~ < k . bs nwords {
        ? != ( nurl_peek w k ) 0 { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ bitset_none Bitset bs → b { ^ ? ( bitset_any bs ) F T }

@ bitset_all Bitset bs → b {
    : s w . bs words
    : i nw . bs nwords
    ? == . bs nbits 0 { ^ T } {}
    : i rem % . bs nbits 64
    : ~ i k 0
    ~ < k nw {
        ? & == k - nw 1 != rem 0 {
            : i expect - << 1 rem 1
            ? == & ( nurl_peek w k ) expect expect {} { ^ F }
        } {
            ? == ( nurl_peek w k ) -1 {} { ^ F }
        }
        = k + k 1
    }
    ^ T
}

@ __bitset_min i a i b → i { ^ ? < a b a b }

@ bitset_and_with Bitset a Bitset b → v {
    : s wa . a words
    : s wb . b words
    : i n ( __bitset_min . a nwords . b nwords )
    : ~ i k 0
    ~ < k n { ( nurl_poke wa k & ( nurl_peek wa k ) ( nurl_peek wb k ) ) = k + k 1 }
    // limbs of `a` beyond `b` AND with 0
    ~ < k . a nwords { ( nurl_poke wa k 0 ) = k + k 1 }
}

@ bitset_or_with Bitset a Bitset b → v {
    : s wa . a words
    : s wb . b words
    : i n ( __bitset_min . a nwords . b nwords )
    : ~ i k 0
    ~ < k n { ( nurl_poke wa k | ( nurl_peek wa k ) ( nurl_peek wb k ) ) = k + k 1 }
}

@ bitset_xor_with Bitset a Bitset b → v {
    : s wa . a words
    : s wb . b words
    : i n ( __bitset_min . a nwords . b nwords )
    : ~ i k 0
    ~ < k n {
        : i x ( nurl_peek wa k )
        : i y ( nurl_peek wb k )
        ( nurl_poke wa k - | x y & x y )
        = k + k 1
    }
}

@ bitset_clone Bitset bs → Bitset {
    : Bitset out ( bitset_new . bs nbits )
    : s src . bs words
    : s dst . out words
    : ~ i k 0
    ~ < k . bs nwords { ( nurl_poke dst k ( nurl_peek src k ) ) = k + k 1 }
    ^ out
}

@ bitset_each_set Bitset bs ( @ v i ) f → v {
    : i nb . bs nbits
    : ~ i bit 0
    ~ < bit nb {
        ? ( bitset_test bs bit ) { ( f bit ) } {}
        = bit + bit 1
    }
}

@ bitset_free Bitset bs → v {
    ? != 0 # i . bs words { ( nurl_free . bs words ) } {}
}
