### Fixed

- **A value holding a result whose error has a `% Drop` is dropped**
  (Agora #539). A struct field or an enum payload `! i Res`, with Res
  having a `% Drop`, was released by nobody (a leak that LeakSanitizer's
  stack scan had hidden). The drop-glue test looked only at a result's Ok
  payload. A try over a cursor of such a parameter's field
  (`: !i Res q ( getr b )  \ q`) now hands its failure back as lent, as
  `^ q` does. Taken for owned, the caller released the parameter's own
  error. The three `try_nc_error_*` probes now run clean under strict
  LSan and leave `lsan_strict.txt`.
