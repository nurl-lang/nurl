// The imported half of diag_duplicate_type: a struct and a global whose
// names another file also picked. Nothing is wrong with THIS file — the
// conflict exists only once both are in one program.
: Shape {
    i w
    i h
}

: ~ i g_shared_count 0
