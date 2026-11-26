@ main → i {
    : ~ i s 0
    : ~ i i 0
    ~ < i 4 {
        : ~ i j 0
        ~ < j 3 {
            ? == j 1 { = j + j 1 continue } {}
            = s + s * i j
            = j + j 1
        }
        = i + i 1
    }
    ^ s
}
