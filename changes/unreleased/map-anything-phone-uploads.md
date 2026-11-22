### Fixed

- **map-anything serve: phone uploads no longer fail with "network error"** (map-anything 0.8.1). The upload page sliced every file with `file.slice()`, which a phone browser can fail to read for a file picked from its gallery; files up to 32 MiB now go whole, larger ones are read as a stream and sent in pieces from memory, unreadable files are reported as such, and failed pieces are retried.
