// diag_init_int_to_enum.nu — initialising an enum binding from a bare
// number. `: Color c 7` wrapped the 7 into the enum shape and
// ASSEMBLED — the tag names no variant and every later match walked
// past it, silently.
: | Color { Red Green Blue }

@ main → i {
    : Color c 7
    ^ 0
}
