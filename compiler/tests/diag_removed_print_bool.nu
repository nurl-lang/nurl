// diag_removed_print_bool.nu — the removed builtin names its cure, and
// the cure has to COMPILE.
//
// `nurl_print_bool` was `nurl_println` of `? b `true` `false``, wrote
// straight to stdio (invisible to the capture buffer and NURL_IO_LOCK),
// and went with the print-family rename. Edit distance would never
// reach the replacement, so the diagnostic carries the migration.
//
// The ternary arms in that replacement are STRING LITERALS, and NURL
// writes those in backticks — which a backtick-delimited diagnostic
// cannot contain. The message used to substitute single quotes and so
// printed an example that is not NURL syntax; `__diag_lit` pokes the
// real quotes in at runtime. This golden is what holds that.
$ `stdlib/core/io.nu`

@ main → i {
    ( nurl_print_bool T )
    ^ 0
}
