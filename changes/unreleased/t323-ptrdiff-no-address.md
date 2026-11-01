### Fixed

- **`nurl_str_find` on a temporary's text compiles and frees the
  temporary** (Agora #323). The index it returns is the difference of two
  addresses. The compiler took that difference to carry the haystack's
  address and summarised the function as handing back its argument. A
  temporary String's view handed to it was therefore refused, or kept
  alive and never freed. A subtraction now hands on only its left
  operand's address.
