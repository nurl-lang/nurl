// diag_dup_enum_name.nu — two enums with the same name. The struct
// declaration path has had this flat-namespace guard for a while; the
// enum path emitted a second `%A = type` plus duplicate variant
// globals — errors only clang reported, location-free.
: | A { X Y }
: | A { Z }

@ main → i {
    ^ 0
}
