### Changed

- **nurlc compiles itself in 15.7% less memory and 1.2% fewer instructions.** Self-compile on a fixed input: peak RSS 248,406 → 209,113 KB (−39 MB); callgrind 24,819.7M → 24,520.7M instructions. Two causes:
  - **The print buffer.** `nurl_print_buf_stop` copied the captured bytes into a new string. nurlc captures its whole module IR, tens of megabytes, so the copy and its buffer were both live at the compile's peak. A frame that holds the whole buffer, at least 64 KB, now hands the buffer itself back, shrunk to fit. The next write starts a new buffer. A smaller frame is copied as before. The block is counted as the copy was, so allocation and leak accounting are unchanged.
  - **The `--unsafe-report` list.** Every compile built and searched the list of `unsafe` items, though only `--unsafe-report` reads it. Each new line was checked by searching a fresh copy of the whole list, so the cost grew with the square of the number of items. The list is now built only under that flag, and a line already listed is found by its key.

  Generated code and the unsafe report are byte-identical. No source changes.
