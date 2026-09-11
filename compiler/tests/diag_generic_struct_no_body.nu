// diag_generic_struct_no_body.nu — a generic struct declaration whose
// body is missing. The template scan skipped to the next '{' ANYWHERE in
// the file, so this declaration swallowed the whole function below it —
// `main` included. The compiler exited 0 and the only report was the
// linker's "undefined reference to `main'", with no source location.

: S [T]

@ main → i {
    ( nurl_print `unreachable\n` )
    ^ 0
}
