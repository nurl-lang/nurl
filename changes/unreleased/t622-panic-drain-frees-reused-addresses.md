### Fixed

- **What a destructor allocates and frees while a panic unwinds is
  freed** (Agora #622). A panic's drain records the address of every
  buffer it frees and skips a second free of one, because a binding's
  slot can hold an address another registration also reaches. The record
  held addresses only, and each buffer went back to the allocator at
  once: the next allocation a destructor made — the message a `% Drop`
  builds — came back from malloc at an address already in the record,
  and its own free was skipped. A recovered panic with a `Vec` of a
  hundred such elements live leaked ninety-nine allocations, in every
  release build; AddressSanitizer's quarantine keeps freed addresses
  away from malloc, so the sanitizer run saw none of it. The drain now
  keeps the buffers it frees until it ends and hands them back to the
  allocator then, so an address in its record names one block for as long
  as the record lasts: a second free of a block is still skipped, and the
  free of a new block never is. A free or an allocation outside a drain
  runs the instructions it did (measured: a million `String`s made and
  dropped, 312,261,108 instructions before and after).

### Changed

- **`compiler/tests/run_san_tests.sh` runs the panic tests (`panic_*`) a
  second time with ASan's quarantine off** (`quarantine_size_mb=0`,
  Agora #622), where malloc hands a freed address straight back as it
  does in a release build. With the runtime as it was, that pass reports
  the leak in all of them.
