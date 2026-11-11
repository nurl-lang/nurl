// diag_struct_holds_itself_by_value.nu — a struct that holds a value of
// its own type has no finite size (agora #661): through an option, a
// result, a second struct, a chain of three, a generic's instance. Each is
// refused at the field the way starts at, with the fields of the cycle
// named. Only the field typed as the struct itself was refused before; the
// others reached clang ("Cannot allocate unsized type") or never ended a
// type walk (a segfault of the compiler).

$ `stdlib/core/string.nu`

: Opt { String s ? Opt next }

// (An error ends its declaration and the one after it is skipped while the
// parser finds its feet: a plain struct stands between the cases.)
: Pad1 { i a }

: Res { i v ! Res i r }

: Pad2 { i a }

: Direct { i v Direct next }

: Pad3 { i a }

: A { String s B b }

: B { i w A a }

: P { i x Q q }

: Q { i y ? R r }

: R { i z ! P i back }

: Wrap [T] { T inner i n }

: Loop { i k ( Wrap Loop ) w }

@ main → i {
    ^ 0
}
