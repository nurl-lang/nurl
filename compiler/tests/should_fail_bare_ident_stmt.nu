// should_fail_bare_ident_stmt.nu — bare-callable-as-statement check.
//
// `nurl_print` is an FFI runtime function. Writing it without parens
// as a statement is the classic "forgot the parens" foot-gun: the
// compiler parses `nurl_print` as a value (a name lookup) whose
// result is discarded, then parses the string literal as its own
// (also discarded) expression statement. Grammar-legal, semantically
// dead.
//
// Post-fix (gen_stmt bare-callable check): the compiler dies at the
// first bare-callable-as-statement site with a `( name args )`-cure
// pointer. Expect COMPILE FAIL.
@ main → i {
  nurl_print `oops, forgot parens\n`
  ^ 0
}
