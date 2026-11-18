### Fixed

- **A join cursor pushed into a Vec, or handed to a function that keeps it, no longer leaks its sources** (AGORA-840). With `: ~ String cur ? == k 1 a b  ( vec_push [String] d cur )`, the push was given a copy, and neither `a` nor `b` was released. Each now drops its own value.
