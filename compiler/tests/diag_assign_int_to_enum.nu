// diag_assign_int_to_enum.nu — assigning a bare number into an enum
// binding. `= c 7` wrapped the 7 into the enum shape and ASSEMBLED —
// a number became an enum value whose tag names no variant, and every
// later match walked past it, silently. The regression shape is the
// sharp one: the preceding `Red` initialiser used to leave an ident
// residue that blessed the wrap.
: | Color { Red Green Blue }

@ main → i {
    : ~ Color c Red
    = c 7
    ^ 0
}
