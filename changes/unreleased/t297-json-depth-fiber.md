### Fixed

- **A deeply nested JSON document crashed the whole process when parsed on a fiber** (Agora #297). `JSON_MAX_DEPTH` was 1024, sized for a thread's 8 MB stack, but every walk of a `Json` value recurses once per level, and a fiber has 64 KB. An async HTTP server parses each request body on one. A body of 250 `[` followed by 250 `]` hit the fiber's guard page with a SIGSEGV that took every connection down: in the parse, which took 352 bytes a level. After Agora #291's parser (64 bytes a level), `json_stringify` still did so from 550 levels, and the drop at the old cap.
  
  The cap is now **256**, as `XML_MAX_DEPTH` and `YAML_MAX_DEPTH` are. 256 levels is at most 32 KB of stack for the deepest walk (`__json_emit`, 128 bytes a level), half a fiber's.
  
  A document nested deeper than 256 now fails with `Overflow` at the bracket that went past the cap; between 257 and 1024 levels it parsed before. JSONTestSuite's y_/n_ verdicts are unchanged; `i_structure_500_nested_arrays` (implementation-defined) is now refused.
  
  `compiler/tests/json_deep_fiber.nu` runs the parse, `json_stringify`, `json_pretty`, `json_clone`, `json_eq` and the drop at the cap on a fiber; with the old cap it dies with SIGSEGV.
