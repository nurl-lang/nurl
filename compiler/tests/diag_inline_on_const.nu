// diag_inline_on_const.nu — `inline` on a non-function declaration
// (grammar v2.7).
//
// `inline` is an attribute on a definition, and `@` is the only
// declaration that has one. Left pending it would drift onto the next `@`
// the parser reaches — after an import boundary, a function in a different
// file — which is the bug `pub` had before v2.0 made it read-and-clear.

inline : i LIMIT 4096

@ main → i { ^ 0 }
