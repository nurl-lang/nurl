// diag_generic_fn_no_body.nu — a generic function declaration with no
// body. The template pre-scan walked to the next '{' ANYWHERE in the
// file, so this declaration swallowed the function below it as its own
// body: the compiler exited 0, emitted a module with no `main`, and the
// only report was the linker's "undefined reference to `main'" with no
// source location. A closure type is always parenthesised, so an '@' at
// paren depth zero ends the walk.

@ f [T] → T

@ main → i {
    ( nurl_print `unreachable\n` )
    ^ 0
}
