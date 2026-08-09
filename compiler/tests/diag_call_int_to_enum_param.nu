// diag_call_int_to_enum_param.nu — passing a bare number where an enum
// is declared. An enum is a closed set of named variants: '( show 7 )'
// against three variants used to assemble into an out-of-range "tag"
// the callee's match could never hit, silently.
: | Color { Red Green Blue }

@ show Color c → i {
    ^ 0
}

@ main → i {
    ^ ( show 7 )
}
