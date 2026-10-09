// H105: an instance of a generic function is compiled after its callers, so the call did not ask it whether its result was its own — the temporary it handed back was freed under the result.
$ `stdlib/core/string.nu`

@ same [T] T tag s x → s { ^ x }

@ main → i {
    : s r ( same [i] 0 ( nurl_str_cat `a temporary ` `string` ) )
    ( nurl_println r )
    ^ 0
}
