// empty_string_shared.nu — an empty owned string allocates nothing.
//
// Every empty copy — `( nurl_str_cat `` `` )`, an empty slice, a lookup
// miss handing back a fresh `` — is the runtime's one shared empty string
// (stdlib/runtime_core.c §9a), not a block of its own: such copies were a
// third of a self-compile's allocations. The shared string is released
// like any other owned string, a String grown from it gets a block of its
// own holding what it held, and a panic that unwinds over frames holding
// empty strings reclaims everything else and leaves the shared one alone.

$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ allocs → i { ^ ( nurl_alloc_count ) }

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

// A lookup that misses: a fresh empty string the caller owns.
@ lookup s key → s {
    ? ( nurl_str_eq key `hit` ) { ^ ( nurl_str_cat key `!` ) } {}
    ^ ( nurl_str_cat `` `` )
}

// Owned locals, empty and not, live in a frame a panic unwinds out of.
@ explode i k → v {
    : s a ( lookup `miss` )
    : s b ( lookup `hit` )
    : s c ( nurl_str_slice b 9 2 )
    : String d ( string_from a )
    ? > k 0 { ( panic `boom` ) } {}
    ( nurl_print_int + + + ( nurl_str_len a ) ( nurl_str_len b ) ( nurl_str_len c ) ( string_len d ) )
}

// A String grown from the shared empty string owns a block of its own;
// both are dropped when this returns.
@ grow_from_empty → v {
    : String g ( string_adopt ( lookup `miss` ) )
    ( string_push_str g `grown` )
    ( string_push_char g 33 )
    ( nurl_print ( string_data g ) ) ( nurl_print `\n` )
    : String h ( string_adopt ( nurl_str_slice `xyz` 0 0 ) )
    ( string_push_str h `` )
    ( nurl_print `still empty: ` ) ( nurl_print_int ( string_len h ) ) ( nurl_print `\n` )
}

@ main → i {
    // Empty copies: no allocation at all.
    : i a0 ( allocs )
    : ~ i total 0
    : ~ i k 0
    ~ < k 1000 {
        : s e1 ( nurl_str_cat `` `` )
        : s e2 ( nurl_str_slice `abc` 3 5 )
        : s e3 ( lookup `miss` )
        : s e4 ( nurl_str_cat3 e1 e2 e3 )
        = total + total + + + ( nurl_str_len e1 ) ( nurl_str_len e2 ) ( nurl_str_len e3 ) ( nurl_str_len e4 )
        = k + k 1
    }
    ( nurl_print `empty copies allocated: ` ) ( nurl_print_int - ( allocs ) a0 ) ( nurl_print `\n` )
    ( nurl_print `total length: ` ) ( nurl_print_int total ) ( nurl_print `\n` )

    // The runtime keeps the latest panic message until the next panic
    // replaces it: take that one block before counting.
    : !v PanicInfo warm ( recover \ → v { ( explode 1 ) } )
    ?? warm { T _ → {} F _ → {} }
    : i l0 ( live )

    ( grow_from_empty )

    // A panic over a frame of empty and non-empty owned strings.
    : ~ i caught 0
    : ~ i r 0
    ~ < r 3 {
        : !v PanicInfo pr ( recover \ → v { ( explode r ) } )
        ?? pr { T _ → {} F _ → { = caught + caught 1 } }
        = r + r 1
    }
    ( nurl_print `\npanics caught: ` ) ( nurl_print_int caught ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
