### Fixed

- **A drop hook of the program's own is checked like a `% Drop`** (AGORA-384). A struct with its own `@ H_drop sink H h → v { … }` hook, or a generic handle with `@ Holder_drop [T] …`, was trusted as a library handle: one given a view of a binding declared after it read freed memory when the hook ran at the end of the scope. That is refused now, as for a `% Drop` type. Declare the view's source before the holder. The standard library's own hooks are unchanged.
