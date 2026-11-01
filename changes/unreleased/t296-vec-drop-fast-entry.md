### Performance

- **A String or `( Vec u )` drop no longer saves six registers first**
  (Agora #296). `nurl_vec_drop` held its element loop in the same body,
  so every call pushed six callee-saved registers before it looked at
  `elem_drop`. A String, a `( Vec u )` and a Json leaf have no element
  to drop. The element loop is now `nurl__vec_drop_elems`, out of line
  and tail-called only when there is an `elem_drop`. `nurl_vec_drop`
  frees the buffer and the control block itself and keeps only the
  control block across a call. Instructions in `nurl_vec_drop` per call
  (x86-64, clang 18 -O2, the same with ThinLTO):

  | | before | after |
  |---|---|---|
  | String with its own buffer | 41 | 24 |
  | packed String (data inside the control block) | 33 | 15 |
  | empty Vec (no buffer) | 30 | 12 |
  | view (`cap < 0`) | 7 | 9 |

  The entry is now small enough for LTO to inline it at its call sites.
  Parsing and dropping `{"id":7,"name":"widget","tags":["tag3","tag5"],"price":12.5,"ok":true}`
  20 000 times (callgrind):
  the drop functions run 8.92 M instructions instead of 10.40 M (−14 %),
  and the whole program 102.86 M instead of 104.22 M. A Vec whose
  elements have a destructor runs two more instructions before its loop.
  What is freed, and in what order, is unchanged.
