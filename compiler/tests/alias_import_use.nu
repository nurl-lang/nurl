// alias_import_use.nu — exercises import aliases and mod::symbol namespacing.
//
// The alias `m` causes every top-level @ function in alias_import_mod.nu to
// land in the IR under the mangled name `m__name`; `m::name` at the call
// site lexes into the same single identifier `m__name`, so dispatch works
// without any further lookup machinery.
//
// Expected output:
//   5
//   12
//   14

$ `compiler/tests/should_fail_alias_import_mod.nu` m

@ main → v {
  ( nurl_print_int ( m::ai_add 2 3 ) )     // 5
  ( nurl_print_int ( m::ai_mul 3 4 ) )     // 12
  ( nurl_print_int ( m::ai_double 7 ) )    // 14 (internal ai_add call was rewritten too)
}
