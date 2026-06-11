// stdlib/ext/uuid.nu — UUID v4 and v7 generation
//
// RFC 9562 compliant UUID generation.
//
//   ( uuid_v4 )            → String   random UUID (version 4)
//   ( uuid_v7 )            → String   time-ordered UUID (version 7)
//   ( uuid_parse s )       → ? ( Vec u )  parse 36-char string to 16 bytes
//   ( uuid_format bytes )  → String   format 16 bytes to 36-char string

$ `stdlib/core/string.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/time.nu`

// Helper: push n hex nibbles of val to out (most significant first)
@ __uuid_push_hex String out i val i nibbles → v {
    : ~ i i - nibbles 1
    ~ >= i 0 {
        : i shift * i 4
        : i v & >> val shift 15
        ( string_push_char out ? < v 10 { + 48 v } { + 87 v } )
        = i - i 1
    }
}

// UUID v4: random UUID
// Generate 16 random bytes, set version to 4, variant to RFC 4122
@ uuid_v4 → String {
    : String raw ( rand_hex_str 16 )  // 32 random hex chars
    : String out ( string_with_cap 36 )

    : ~ i i 0
    ~ < i 32 {
        // Insert dashes at 8-4-4-4-12 positions
        ? == i 8 { ( string_push_char out 45 ) } {}
        ? == i 12 { ( string_push_char out 45 ) } {}
        ? == i 16 { ( string_push_char out 45 ) } {}
        ? == i 20 { ( string_push_char out 45 ) } {}

        : ~ i c ( string_get raw i )
        ? == i 12 { = c 52 } {}  // version 4 ('4')
        ? == i 16 { = c 56 } {}  // variant 1 (8, 9, a, or b; we use '8')

        ( string_push_char out c )
        = i + i 1
    }

    ( string_free raw )
    ^ out
}

// UUID v7: time-ordered UUID
// Unix timestamp in milliseconds (48 bits) + random data (74 bits)
@ uuid_v7 → String {
    : i ts ( now_ms )
    : String raw ( rand_hex_str 10 )  // 20 random hex chars
    : String out ( string_with_cap 36 )

    // Timestamp: 48 bits = 12 hex chars. Group 1 (8) and Group 2 (4).
    ( __uuid_push_hex out >> ts 16 8 )
    ( string_push_char out 45 )
    ( __uuid_push_hex out & ts 65535 4 )
    ( string_push_char out 45 )

    // Group 3: '7' + 12 bits of randomness (3 hex chars)
    ( string_push_char out 55 )  // '7'
    ( string_push_char out ( string_get raw 0 ) )
    ( string_push_char out ( string_get raw 1 ) )
    ( string_push_char out ( string_get raw 2 ) )
    ( string_push_char out 45 )

    // Group 4: '8' + 12 bits of randomness (3 hex chars)
    ( string_push_char out 56 )  // '8'
    ( string_push_char out ( string_get raw 3 ) )
    ( string_push_char out ( string_get raw 4 ) )
    ( string_push_char out ( string_get raw 5 ) )
    ( string_push_char out 45 )

    // Group 5: 48 bits of randomness (12 hex chars)
    : ~ i i 6
    ~ < i 18 {
        ( string_push_char out ( string_get raw i ) )
        = i + i 1
    }

    ( string_free raw )
    ^ out
}

// Parse a 36-character UUID string into 16 bytes
@ uuid_parse s input → ?( Vec u ) {
    : i len ( nurl_str_len input )
    ? != len 36 { ^ @ ?( Vec u ) { F } } {}

    : ( Vec u ) bytes ( vec_with_cap [u] 16 )
    : ~ i i 0
    : ~ i bi 0
    ~ < i 36 {
        : i c ( nurl_str_get input i )
        // Skip dashes at 8, 13, 18, 23
        ? | | | == i 8 == i 13 == i 18 == i 23 {
            ? != c 45 {
                ( vec_free [u] bytes )
                ^ @ ?( Vec u ) { F }
            } {}
            = i + i 1
        } {
            : i c2 ( nurl_str_get input + i 1 )

            : i high ( __uuid_hex_to_int c )
            : i low ( __uuid_hex_to_int c2 )

            ? | == high -1 == low -1 {
                ( vec_free [u] bytes )
                ^ @ ?( Vec u ) { F }
            } {}

            ( vec_push [u] bytes # u | << high 4 low )
            = i + i 2
        }
    }

    ^ @ ?( Vec u ) { T bytes }
}

// Format 16 bytes into a 36-character UUID string
@ uuid_format ( Vec u ) bytes → String {
    ? != ( vec_len [u] bytes ) 16 { ^ ( string_from `00000000-0000-0000-0000-000000000000` ) } {}

    : String out ( string_with_cap 36 )
    : ~ i i 0
    ~ < i 16 {
        ? | | | == i 4 == i 6 == i 8 == i 10 { ( string_push_char out 45 ) } {}

        : ?u got ( vec_get [u] bytes i )
        : i b # i ?? got { T v → v F → # u 0 }

        ( __uuid_push_hex out b 2 )
        = i + i 1
    }
    ^ out
}

// Helper: hex char to integer (0-15)
@ __uuid_hex_to_int i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}  // '0'-'9'
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}  // 'a'-'f'
    ? & >= c 65 <= c 70 { ^ + 10 - c 65 } {}  // 'A'-'F'
    ^ -1
}
