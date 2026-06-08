// Helper for pub_trait_ffi_visibility.nu — the DELIBERATELY UNENFORCED
// half of the grammar-v2 visibility contract.
//
// The file is in strict mode (vtf_anchor is `pub`), and only the anchor
// fn and the `VtfWidget` struct are exported. The trait `VtfShow`, its
// `VtfShow (VtfWidget)` impl method, and the `abs` FFI are all UNMARKED
// — yet they must stay usable from an importer, because trait dispatch
// is type-mangled (not name-resolved) and FFI symbols are linker-level
// globals. See spec §3.3.

pub @ vtf_anchor → i { ^ 0 }

pub : VtfWidget { i id }

% VtfShow [T] {
    @ vtf_show T x → i
}

% VtfShow ( VtfWidget ) {
    @ vtf_show VtfWidget w → i { ^ . w id }
}

& `c` @ abs i x → i
