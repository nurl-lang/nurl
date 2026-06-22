// hex_literals.nu — `0x…` / `0b…` integer literals and their use in
// expressions, match patterns, enum field-constraints, and global
// initialisers (pointer / aggregate / integer). Regression guard for
// the literal-lexing + global-init + match-literal codegen.

$ `stdlib/core/string.nu`

: s g_ptr 0  // pointer-typed global → `null` initialiser
: String g_str 0  // aggregate global → `zeroinitializer`
: i g_mask 0xFF  // hex integer-global initialiser

@ classify i op → i {
    ?? op {
        0x00 → 1
        0b1010 → 2
        0xCB → 3
        0xFF → 4
        _ → 0
    }
}

: | Tagged { TagCode i TagOther i }

// Enum field-constraint with a hex literal.
@ name_of Tagged t → s {
    ?? t {
        TagCode 0x90 → `LY`
        TagCode 0xFF → `IE`
        TagCode c → `code`
        TagOther _ → `other`
    }
}

@ main → i {
    // Literals in expressions.
    ( nurl_print ( nurl_str_int 0xFF ) ) ( nurl_print ` ` )  // 255
    ( nurl_print ( nurl_str_int 0b1010 ) ) ( nurl_print ` ` )  // 10
    ( nurl_print ( nurl_str_int & 0xF0 0x3C ) ) ( nurl_print ` ` )  // 0x30 = 48
    ( nurl_print ( nurl_str_int << 0x1 4 ) ) ( nurl_print ` ` )  // 16
    ( nurl_print ( nurl_str_int g_mask ) ) ( nurl_print `\n` )  // 255

    // Literals in match patterns.
    ( nurl_print ( nurl_str_int ( classify 0x00 ) ) )
    ( nurl_print ( nurl_str_int ( classify 0b1010 ) ) )
    ( nurl_print ( nurl_str_int ( classify 0xCB ) ) )
    ( nurl_print ( nurl_str_int ( classify 0xFF ) ) )
    ( nurl_print ( nurl_str_int ( classify 0x42 ) ) )
    ( nurl_print `\n` )

    // Enum field-constraints.
    ( nurl_print ( name_of @ Tagged { TagCode 0x90 } ) ) ( nurl_print ` ` )
    ( nurl_print ( name_of @ Tagged { TagCode 0xFF } ) ) ( nurl_print ` ` )
    ( nurl_print ( name_of @ Tagged { TagCode 0x01 } ) ) ( nurl_print `\n` )

    // Pointer / aggregate globals initialise cleanly (null / zeroinit).
    ( nurl_print ( nurl_str_int ? == 0 # i g_ptr 1 0 ) ) ( nurl_print ` ` )  // 1
    ( nurl_print ( nurl_str_int ( string_len g_str ) ) ) ( nurl_print `\n` )  // 0
    ^ 0
}
