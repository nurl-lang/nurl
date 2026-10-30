// diagprobes: the fixed nesting limit's own wording.
// tools/check_diag_coverage.sh compiles this with --max-nesting-fixed=4;
// with no flag it compiles.
@ main → i {
    ^ + 1 + 1 + 1 + 1 + 1 + 1 0
}
