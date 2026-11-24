@ main → i {
    : ~ i n 0
    : ~ i acc 0
    ~ < n 10 {
        = n + n 1
        ? == n 3 { continue } {}
        ? == n 8 { break } {}
        = acc + acc n
    }
    ^ acc
}
