// ============================================================
// test_11_fat_strings.nu
// Tarkoitus: Testata merkkijonojen käsittelyä "{ ptr, len }"
// fat pointer -layoutilla hyödyntäen NURLin struct-aggregaatteja,
// raw-pointer indeksointia ja FFI-liitäntää.
// ============================================================

// FFI-liitännät libc:hen — `strlen` tulee nykyisin kääntäjän
// preamblesta globaalisti (PURIFY.md Phase 5 scaffolding,
// 2026-05-23), joten per-tiedosto-redeklaraatio jäi pois.
& `libc`

@ write i fd s buf i count → i

// 1. Määritellään Fat Pointer -merkkijono, sama layout kuin slicellä!
: String {
    s ptr
    i len
}

// 2. Rakentaja: Ottaa turvattoman i8* C-merkkijonon, laskee
// sen pituuden dynaamisesti ja rakentaa turvallisen String-structin.
@ to_string s raw → String {
    : i length ( strlen raw )
    ^ @ String { raw length }
}

// 3. Turvallinen tulostus: Käyttää libc:n write-funktiota.
// Ei välitä null-päätteistä, tulostaa tasan 'len' tavua.
@ safe_print String str → i {
    ( write 1 . str ptr . str len )
    ( write 1 `\n` 1 )
    ^ 0
}

// 4. Turvallinen merkin haku indeksistä (palauttaa merkin ASCII-koodin i:nä)
@ char_at String str i index → i {
    // Bounds check: Jos index >= len, palautetaan -1 (eli ~0)
    ^ ? >= index . str len
    ~ 0
    // cast_expr (#): raw pointer luetaan (. ptr idx), ja 
    // tuloksena oleva i8 pakotetaan i:ksi (i64)
    # i . . str ptr index
}

@ main → i {
    ( nurl_print `== Fat Pointer Strings Test ==\n` )

    // Luodaan turvalliset merkkijonot raw-literaaleista
    : String s1 ( to_string `hello` )
    : String s2 ( to_string `NURL!` )

    ( safe_print s1 )
    ( safe_print s2 )

    // Haetaan merkkejä (ASCII-arvot)
    : i char1 ( char_at s1 0 )  // 'h' = 104
    : i char2 ( char_at s2 4 )  // '!' = 33

    // Yritetään lukea yli rajojen
    : i char3 ( char_at s2 10 )  // Out of bounds = -1 (~0)

    ( nurl_print `char1 ('h'): ` )
    ( nurl_print ( nurl_str_int char1 ) )
    ( nurl_print `\n` )

    ( nurl_print `char2 ('!'): ` )
    ( nurl_print ( nurl_str_int char2 ) )
    ( nurl_print `\n` )

    ( nurl_print `char3 (OOB): ` )
    ( nurl_print ( nurl_str_int char3 ) )
    ( nurl_print `\n` )

    // Lasketaan tarkistussumma:
    // s1.len (5) + s2.len (5) + 'h' (104) + '!' (33) + OOB (-1) = 146
    : i sum + + + + . s1 len . s2 len char1 char2 char3

    ( nurl_print `CHECKSUM: ` )
    ( nurl_print ( nurl_str_int sum ) )
    ( nurl_print `\n` )

    // Palautetaan 0 jos kaikki OK
    ^ ? == sum 146 0 1
}
