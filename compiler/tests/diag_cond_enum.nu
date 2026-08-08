// diag_cond_enum.nu — an enum condition: which variant would be
// 'false'? The tag comparison the user actually means must be written
// out ('? == c Red { … }' or a '??' match).
: | Color { Red Green Blue }

@ main → i {
    : Color c Red
    ? c { ^ 1 } {}
    ^ 0
}
