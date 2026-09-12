// diag_pub_on_import.nu — the 'pub' prefix on a '$' import.
//
// The grammar excludes import_decl from the visibility prefix: an import
// inlines another file's declarations and defines no symbol of its own, so
// there is nothing to export. It was read-and-cleared in silence, which is
// worse than a no-op — a file enters strict visibility at its FIRST 'pub',
// so a file whose only 'pub' sat on its import stayed in legacy mode with
// every function globally callable, and said nothing about it.
//
// 'simd' and 'inline' in this exact position have been diagnostics since
// v2.6. This is the same rule in the spelling that was left out.
pub $ `stdlib/core/string.nu`

@ main → i {
    ^ 0
}
