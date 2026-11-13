### Fixed

- **The Windows compiler gets the stack a Linux one has** (found landing Agora #824). `build.bat` links the compiler stages, `-O0` bootstrap and `-O2` shipped, with an 8 MB stack reserve. Before, they had Windows's 1 MB default. The bootstrap stage compiling `nurlc.nu` needed between 0.9 and 1 MB, so one more local on the recursive walk ran it out of stack (exit `0xC00000FD`). The shipped `nurlc.exe` would likewise fail on a deeply nested program that the Linux compiler compiles.
