### Fixed

- **A binding moved into a join of literals written as a field ends its views there** (Agora #828). Take `: ~ Y yy @ Y { ? k @ X { xs } @ X { ys } 1 }`, then `( vec_reserve . . yy x v 4096 )`, then reading a slice of `xs` taken before. This was a heap-use-after-free. It is refused since a join's per-arm stores (Agora #757, github#1836). Two probes now guard it, and the open-hole entry is gone.
