### Fixed

- **A CUDA program links on WSL** (Agora #503, nurl.sh). WSL keeps the
  NVIDIA driver's `libcuda.so.1` in `/usr/lib/wsl/lib`, a directory that
  only `/etc/ld.so.conf.d` lists. The dynamic loader finds it there, but
  neither linker searches it, so every program that imports
  packages/gpu (nurllama, onnx, …) failed to link with "unable to find
  library -l:libcuda.so.1": the release toolchain's bundled ld.lld always,
  and a system clang unless `LIBRARY_PATH` was set. nurl.sh already asked
  the loader's cache (`ldconfig -p`) whether the driver was there. It now
  also links the file that cache resolves the soname to, for the machine's
  ABI (libcuda, libnvrtc, libX11). The executable still records only the
  soname, so at run time the loader finds the library where it found it
  at link time. Nothing is hard-coded, and a library the cache does not
  know is still linked as `-l:<soname>`.
