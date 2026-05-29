// forward_enum_payload.nu — forward-referenced types as enum payloads
//
// Regression for ROADMAP "Core Language — Forward References: enum
// variants". An enum variant whose payload type (a struct OR another
// enum) is declared LATER in the file must still be parsed as a
// payload, not misread as a phantom variant. Before the scan_type_names
// pre-pass, `could_be_payload_type` only recognised a payload type that
// was already registered in `syms`, so a forward-referenced payload
// turned into an extra variant and any `??` over the enum reported a
// bogus non-exhaustive match.
//
// Expected output:
//   3
//   200
//   0

// Enum declared BEFORE both of the types it uses as payloads.
: | Shape { Dot Box Geom Hue Color }

// Forward-referenced STRUCT payload.
: Geom { i w i h }

// Forward-referenced ENUM payload.
: | Color { Red Green }

@ shape_val Shape s → i {
    ?? s {
        Dot → ^ 0
        Box g → ^ . g w
        Hue c → ?? c {
            Red → ^ 100
            Green → ^ 200
        }
    }
}

@ main → v {
    : Geom g @ Geom { 3 5 }
    : Shape a @ Shape { Box g }
    ( nurl_print_int ( shape_val a ) )  // 3 — struct payload field

    : Color c Green
    : Shape b @ Shape { Hue c }
    ( nurl_print_int ( shape_val b ) )  // 200 — enum payload, nested match

    : Shape d Dot
    ( nurl_print_int ( shape_val d ) )  // 0 — tag-only variant
}
