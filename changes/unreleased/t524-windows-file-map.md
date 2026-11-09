### Performance

- **`file_map` maps files on Windows** (Agora #524, stdlib/std/mmap.nu).
  On Windows, `file_map` and `file_map_stream` used to read the whole file
  into memory, so every model loader built on them (`gguf_open`, `st_open`,
  torchpt, whisper's ggml, and nurllama's checkpoint directories and
  streamed experts) paid the file's full size in RAM before a tensor was
  touched, and a model bigger than RAM could not be opened at all. They now
  map the file read-only with `CreateFileMappingW` / `MapViewOfFile`, from
  a UTF-8 path widened to UTF-16, with 64-bit sizes. `file_map_stream`
  adds `FILE_FLAG_SEQUENTIAL_SCAN` and `PrefetchVirtualMemory`, the
  counterparts of Linux's `MAP_POPULATE` + `MADV_SEQUENTIAL`. Measured on
  native Windows with a 4 GiB file: opening it went from 7 s and 4 GB of
  private memory to 0 ms and a 4.3 MB working set, and after 1 GiB of it is
  read, private memory is still 8.8 MB, because the pages are the file's
  and shared. The map/unmap sequence is now one runtime entry point,
  `nurl_file_map` / `nurl_file_unmap` (stdlib/runtime_core.c), on every
  platform. POSIX and the unikernel still use `mmap`; wasm, which maps no
  files, still reads the file whole.
