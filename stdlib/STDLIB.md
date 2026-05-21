# NURL Standard Library — Roadmap & työlista

> Priorisoitu suunnitelma + työlista. Järjestys = toteutusjärjestys.
> Aiemmat tasot ovat myöhempien edellytyksiä, eivät vain "tärkeämpiä".

**Merkinnät**
- `[x]` = toteutettu (sijainti suluissa)
- `[ ]` = toteuttamatta
- `(NURL)` = toteutetaan NURL-kielellä runtimein päälle
- `(RT)` = tarvitsee C-rajapintaa `stdlib/runtime.c`:ssä (syscall, libc, libm, libsodium…)
- `(NURL+RT)` = NURL-wrappreri, joka nojaa pieneen RT-lisäykseen

---

## Periaatteet

1. **NURL on suunniteltu LLM:ille.** Stdlib-API:t suunnitellaan niin, että LLM löytää oikean funktion vähäisellä kontekstilla. Yksi tapa tehdä asia, ei viittä.
2. **Single-owner + RC-closuret on muistimalli.** Jokainen API kunnioittaa tätä — funktiot palauttavat omistajuuden tai eivät, dokumentoidusti.
3. **Token-tehokkuus pätee API-suunnittelussakin.** Funktioiden nimet lyhyet mutta yksiselitteiset (`vec_push`, ei `vector_append_element`).
4. **Stdlib kirjoitetaan NURL:lla** aina kun mahdollista. C-runtime (FFI) vain niissä kohdissa joissa NURL ei pärjää (syscallit, libc-rajapinta, libm, libsodium).
5. **Jokainen kirjasto vaatii testit + esimerkin** ennen kuin se merkitään valmiiksi. LLM oppii esimerkeistä.

---

## Nykytila — mitä `runtime.c`:ssä on jo

`runtime.c` (~980 riviä) sisältää kaksi toisistaan erillistä puoliskoa:

**A. Bootstrap-kompilaattorin tuki** (poistetaan kun kääntäjä itsehostuu puhtaasti):
`nurl_lex_*`, `nurl_sym_*`, `nurl_cg_*`, `nurl_get_last_type`/`nurl_set_last_type`,
`nurl_print_buf_start/stop/reset`. **Ei kuulu stdlibiin.**

**B. Stdlib-FFI** (tästä stdlib rakennetaan):
- I/O: `nurl_print`, `nurl_print_int`, `nurl_print_str`, `nurl_print_bool`, `nurl_eprint`, `nurl_eprintln`, `nurl_read_int`
- Raaka-str: `nurl_str_len/get/eq/cat/cat3/cat4/int/float/to_int/slice/starts/find`
- Charit: `nurl_is_alpha/digit/space/alnum_`
- Tiedostot: `nurl_read_file`, `nurl_file_open/read/write/close/exists/size/del`
- Prosessi: `nurl_argc`, `nurl_argv`, `nurl_argv_count`, `nurl_argv_get`, `nurl_exit`
- Muisti: `nurl_alloc`, `nurl_zalloc`, `nurl_realloc`, `nurl_free`, `nurl_memcpy`, `nurl_peek`, `nurl_poke`
- HashMap (string→i64): `nurl_map_new/put/get/has/del/size/free`
- ~~StringBuilder: `nurl_sb_new/add/add_int/add_float/str/len/clear/free`~~ **POISTETTU 2026-05-01** — String elää nyt Vec[u]:n päällä `stdlib/core/string.nu`:ssa.

Huom: `nurl_memset`, `nurl_arena_*`, `read_line`, `flush_stdout`, `dir_*`, aika, env, math,
random, net, process_run eivät ole vielä runtimessa.

---

## Tier 0 — Perusta (pakolliset jotta mikään muu toimii)

Nämä on toteutettava ensin. Ilman näitä yksikään myöhempi kirjasto ei käänny.

### 1. `mem` — muistinhallinnan rajapinta NURL:lle
- [x] `nurl_alloc bytes` → `i8*` (RT, runtime.c)
- [x] `nurl_zalloc bytes` → `i8*` (RT)
- [x] `nurl_realloc p bytes` → `i8*` (RT)
- [x] `nurl_free p` (RT)
- [x] `nurl_memcpy dst src n` (RT)
- [x] `nurl_peek`, `nurl_poke` (i64 index access) (RT)
- [x] `nurl_memset dst byte n` (RT — `runtime.c` §9)
- [x] Tyypitetty wrapperi `alloc [T] n → *T`, `zalloc [T] n → *T` (`stdlib/core/mem.nu`)
- **Status:** Tier 0 `mem` valmis. Arenat siirretty Tier 3:een (ks. `Arena`-kohta) — single-owner + auto-drop kattaa tavallisen käytön, arenoja tarvitaan vain bulk-free -kuvioihin (parseri, compilerin oma työ).

### 2. `string` — owned String -tyyppi
NURL:n nykyinen `s` on raaka `i8*`. Tarvitaan **owned String** -tyyppi.

Raaka-operaatiot (jo olemassa, käytetään pohjana):
- [x] `nurl_str_len`, `nurl_str_get` (RT)
- [x] `nurl_str_eq`, `nurl_str_starts`, `nurl_str_find` (RT)
- [x] `nurl_str_cat`, `nurl_str_cat3`, `nurl_str_cat4` (RT)
- [x] `nurl_str_int`, `nurl_str_float`, `nurl_str_to_int` (RT)
- [x] `nurl_str_slice` (RT)
- ~~`StringBuilder` (`nurl_sb_*`)~~ **poistettu 2026-05-01** — Vec[u] korvasi sen kasvavana byte-puskurina.

Owned `String { s ctl }` — opaque handle Vec[u]-kontrolliblokin ympärille (2026-05-01 layout-vaihto; aiemmin `String { s sb }` StringBuilderin päällä). `ctl` osoittaa samaan 24 B `{data, len, cap}`-blokkiin jonka `vec_with_cap [u]` allokoi. Stdlibin sisällä string-ops viewataan Vec[u]:na private `__sbuf`-helperin kautta. Invariantit: `cap >= len + 1` ja `data[len] == 0` operaatioiden välillä, jolloin `string_data` palauttaa C-yhteensopivan NUL-terminoidun pointterin. Embedded NUL-tavut säilyvät verbatim `[0, len)`:ssä — vain `string_data`:n C-string-kuluttaja näkee truncaation. **`nurl_sb_*` runtime-funktiot poistettiin samalla** — kompileri ei käyttänyt niitä, vain referoi (declare-rivit ja sym_def:t IR-preamblesta poistettu); jäljelle jäänyt SB-koodi `runtime.c §10`:ssä korvattiin `Vec[u]`-suosittelukommentilla.

MVP 1 (`stdlib/core/string.nu`):
- [x] `string_new` → String
- [x] `string_from raw` → String  (kopio raaka `i8*`:sta)
- [x] `string_len str` → i
- [x] `string_data str` → s  (lainattu `i8*`, null-terminoitu; älä vapauta)
- [x] `string_get str idx` → i  (byte at index)
- [x] `string_push_char str c` → v  (Vec[u] vec_push + NUL-seal)
- [x] `string_push_str str raw` → v
- [x] `string_push_int str n` → v
- [x] `string_clear str` → v
- [x] `string_free str` → v  (manuaalinen toistaiseksi — struct-auto-drop on myöhempi Phase)
- [x] `string_eq a b` → b

MVP 2:
- [x] `string_with_cap n` → String  (Vec[u] vec_with_cap + NUL-seal)
- [x] `string_concat a b` → String  (palauttaa uuden)
- [x] `string_ends_with suffix` → b  (tarvittiin uusi RT: `nurl_str_ends`)
- [x] `string_contains needle` → b  (NURL, `nurl_str_find`)
- [x] `string_starts_with prefix` → b  (NURL, `nurl_str_starts`)
- [x] `string_substr from len` → String  (NURL, sb-byte-loop clampilla)
- [x] `string_index_of needle` → `?i`  (`stdlib/core/string.nu` — `nurl_str_find` wrapped, -1 → None)
- [x] `string_to_int` → `! i ParseErr`  (NURL-validointi; `stdlib/core/string.nu` — Empty | BadFormat, atoll-pohja)
- [x] `string_to_float` → `?f`  (`stdlib/core/string.nu` — strict decimal/exp grammar, None on reject. TODO: upgrade to `! f ParseErr` when compiler gains double-in-result support)

MVP 3 (isompi):
- [x] `string_split sep` → `( Vec String )` — non-overlapping split, returns ≥1 element. Empty sep → single-element Vec with full copy. Aina vähintään yksi elementti (Rust-semantiikka). `__split_emit`-helper kerää tavut via `string_with_cap` + `string_push_char`. Testi: `compiler/tests/string_split.nu` (10 case: simple, leading/trailing/consec separators, multi-byte, empty input, sep > str, empty sep). Caller vapauttaa via `vec_free_with` + `string_free`-closure.
- [x] `string_trim`, `string_trim_start`, `string_trim_end` (`stdlib/core/string.nu` — loop-clamp + SB-rebuild; testi: `compiler/tests/string_mvp3.nu`)
- [x] `string_to_lower`, `string_to_upper` (`stdlib/core/string.nu` — ASCII-vain bytewise; testi sama)
- [x] `string_replace from to` (`stdlib/core/string.nu` — non-overlapping occurrence scan; testi sama)
- [x] `string_repeat n`, `string_reverse` (`stdlib/core/string.nu`; testit: `string_mvp3.nu`)

Runtime-lisäykset tähän vaiheeseen:
- ~~`nurl_sb_buf` / `nurl_sb_add_byte` / `nurl_sb_get` / `nurl_sb_new_cap`~~ poistettu 2026-05-01 String-migraation yhteydessä
- [x] `nurl_str_ends` — suffix-tarkistus (RT)
- **Tämä on tärkein yksittäinen kirjasto.** Lähes kaikki muu nojaa string-käsittelyyn.

### 3. `vec` — kasvava taulukko
NURL:ssa on slice-tyyppi `[T`. `Vec[A]` käytännössä opaque-handle heap-kontrolliblokin
(`{data, len, cap}`) yli, peilaten `String`:n omistusmallia (handle by value, mutaatiot
heap-pointerin läpi). MVP toteutettu 2026-04-25 (`stdlib/core/vec.nu`).
- [x] `: Vec [A] { s ctl }` (opaque handle; ctl ⇒ 24 B `nurl_zalloc`)
- [x] `vec_new`, `vec_with_cap n`
- [x] `vec_push x`, `vec_pop` → `?A`
- [x] `vec_get i` → `?A`, `vec_set i x` → `b`
- [x] `vec_len`, `vec_cap`, `vec_is_empty`, `vec_data`, `vec_clear`
- [x] `vec_swap i j`, `vec_reverse`
- [x] `vec_free` (kutsujan vastuulla; `Vec[String]`: vapauta elementit ensin)
- [x] `vec_each f`, `vec_fold init f`
- [x] **Drop-integraatio `vec_free_with`** (`stdlib/core/vec.nu` 2026-04-25):
      `vec_free_with [A] v drop` — kutsuu `drop`-closuren jokaiselle elementille
      `[0..len)`-välillä ennen bufferin + ctl:n vapautusta. NURL:lla ei ole
      type-class-dispatchia → drop välitetään closure-arg:ina per-call (sama
      kuvio kuin `HashMap`:n hash/eq). Bare `vec_free` säilyy triviaali-
      tyypeille (`i`, `f`, `b`); `Vec[String]` / sisäkkäiset `Vec[Vec ...]` /
      `Vec[HashMap ...]` käyttävät `vec_free_with`. Testi: `compiler/tests/vec_drop.nu` (ASan-clean).
      Sivuvaikutus: korjasi `gen_backslash_expr`-luokittelua hyväksymään
      `\ IDENT TYPE_KW →` (single-letter param name kuten `\ String s →`
      tunnistettiin ennen virheellisesti try-operaatioksi).
- [x] `vec_extend dst src` (bitwise-kopio, sama trivial-only-rajoitus kuin
      `vec_map`:lla; testi: `compiler/tests/vec_capacity.nu`, 2026-04-28)
- [x] `vec_reserve n` (varmista cap ≥ len + n; nojaa `__vec_grow`:n päälle;
      negatiivinen tai nolla `n` on no-op; testi: `compiler/tests/vec_capacity.nu`, 2026-04-28)
- [x] `vec_shrink_to_fit` (realloc datan kokoon `len`; jos `len == 0`,
      vapauta puskuri kokonaan; testi: `compiler/tests/vec_capacity.nu`, 2026-04-28)
- [x] `vec_insert i x`, `vec_remove i` (memmove keskeltä; testi:
      `compiler/tests/vec_insert_remove.nu`)
- [ ] `vec_from_array *A n` (pointer + len → Vec, kopioi; FFI ja stdlib-helperit)
- [x] `vec_clone` / `vec_clone_with` (`stdlib/core/vec.nu`, 2026-05-21). Clone-päätös:
      ei kieli-tason Clone-traitia vaan closure-välitys, sama kuvio kuin
      `vec_free` / `vec_free_with`. `vec_clone` = bitwise shallow copy (triviaalit
      alkiot); `vec_clone_with [A] v ( @ A A ) clone` = syväkopio, ajaa `clone`-
      closuren per alkio (`Vec[String]` / sisäkkäiset). Stock-alkioklooni
      `string_clone` (`stdlib/core/string.nu`). Testi: `compiler/tests/clone_basic.nu`
      (ASan + UBSan + leak-detection puhdas).
- [x] `Slice[A]` shipped 2026-05-17 (`stdlib/core/slice.nu`): `Slice[A] { *A data, i len }`, constructors `slice_from_vec` / `slice_sub` / `slice_from_raw`, inspectors `slice_len` / `slice_is_empty` / `slice_data` / `slice_get` / `slice_first` / `slice_last`. Korvaa `vec_data`-pattenrin hot-loopeissa.
- [x] `vec_map f`, `vec_filter pred` (allokoivat uuden Vec:n; lähde koskemattomaksi).
      `vec_map`/`vec_filter` bitwise-kopioivat → triviaalit alkiot; omistaville
      tyypeille `vec_filter_with [A] v pred ( @ A A ) clone` kloonaa säilytetyt
      alkiot (`stdlib/core/vec.nu`, 2026-05-21).
- [x] `vec_find pred`, `vec_any pred`, `vec_all pred` (predikaattipohjaiset)
- [x] `vec_contains target eq_fn`, `vec_index_of target eq_fn`,
      `vec_eq a b eq_fn` (closure-pohjainen tasa-arvo, sama eq-konvention kuin
      `HashMap`:n; testi: `compiler/tests/vec_eq_search.nu`, 2026-04-28).
      Stock-`eq_string` / `eq_int` toimivat closure-wrapperien kautta.
- [ ] `vec_sort_by cmp` (deterministisyys symbol tableille, error-listoille; Ord-versio
      kun trait olemassa)
- [ ] **API-päätös:** `vec_push` palautusarvon semantiikka — sama handle (alias)
      vai unit? Nyt `→ v` on epäselvä; Rustin `&mut self → ()` selkeämpi mutta
      method chaining häviää
- [ ] *(myöhemmin)* iteratorit erillisinä objekteina, drain/split/chunks/windows/
      zip/enumerate, custom allocator -tuki
- **Yhdessä `String`:n kanssa kattaa 80% käytännön ohjelmoinnista.**

### 4. `option` ja `result` — virhekäsittelyn standardit
NURL:ssa on jo `?T` ja `! T E`. Tarvitaan **operaatiot**:
- [x] `opt_map f`, `opt_and_then f`, `opt_unwrap_or default`, `opt_is_some`, `opt_is_none` (NURL — `stdlib/core/option.nu`)
- [x] `res_is_ok`, `res_is_err`, `res_unwrap_or default`, `res_map f`, `res_map_err f`, `res_and_then f` (NURL — `stdlib/core/result.nu`)
- [x] Vakiintuneet error-tyypit: `ParseErr`, `IoErr`, `BoundsErr` (NURL — `stdlib/core/errors.nu`)
- [x] 3-parametrin generics (esim. `[A B E]`) toteutettu: lisätty `nurl_lex_peek4_type` runtimeen ja `gen3`-haara `gen_fn_decl`:iin / `scan_fn_sigs`:iin. Tarvittiin jotta `res_map`-perhe voitiin kirjoittaa.
- **Pakollinen ennen kuin muut kirjastot voivat raportoida virheitä yhdenmukaisesti.**

### 5. `io` — perus stdin/stdout/stderr
- [x] `print s` (RT — `nurl_print`)
- [x] `println s` (RT — `nurl_print_str` tulostaa sanoman + `\n`)
- [x] `eprint s`, `eprintln s` (RT)
- [x] `print_int`, `print_bool` (RT — säilytetään, löytyy jo)
- [x] `read_int` (RT)
- [x] `read_line` → `String` (RT — `nurl_read_line` dynamic-grow buffer; EOF-erotuksen tekee `stdin_eof` — upgrade to `! String IoErr` when Result<String,E> lowering lands)
- [x] `read_all_stdin` → `String` (`stdlib/core/io.nu`, 2026-04-28 — `nurl_read_all_stdin` runtime §13, dynamic-grow malloc → tyhjä String NULLista. Result-rajapinta jätetään myöhempään kun `! String IoErr` allokaatiovirheille tuo arvoa.)
- [x] `flush_stdout`, `flush_stderr` (RT — `nurl_flush_stdout`/`nurl_flush_stderr`; NURL: `( flush )` / `( eflush )` in `stdlib/core/io.nu`)
- **CLI-työkalujen minimi.** Ilman tätä ei voi rakentaa edes "hello world"-tasoista käytännön ohjelmaa.

---

## Tier 1 — Käytännön ohjelmointi (yleisimmät tarpeet)

Kun Tier 0 on valmis, näillä kirjoitat suurimman osan ohjelmista.

### 6. `fs` — tiedostonkäsittely
Raaka:
- [x] `nurl_read_file path` → `i8*` (RT, exitoi virheessä)
- [x] `nurl_file_read/open/write/close/exists/size/del` (RT)

API-pinta (`std/fs.nu`, MVP 2026-04-26):
- [x] `read_file path` → `! String IoErr` (`stdlib/std/fs.nu`; käyttää uutta `nurl_read_file_safe`-runtimea + `nurl_errno_kind`-mappia. Kopioi sisällön omaan `String`-handleen ja `nurl_free`:aa malloc-puskurin. Testi: `compiler/tests/fs_safe.nu`)
- [x] `read_file_bytes path` → `! ( Vec u ) IoErr` (`stdlib/std/fs.nu`, 2026-05-01 — runtime §4 `nurl_read_file_bytes` + sideband `nurl_last_bytes_len`)
- [x] `write_file_bytes path bytes` → `! v IoErr` (`stdlib/std/fs.nu`, 2026-05-01 — `wb` mode)
- [x] `append_file_bytes path bytes` → `! v IoErr` (`stdlib/std/fs.nu`, 2026-05-01 — `ab` mode)
- [x] `write_file path content` → `! v IoErr` (`stdlib/std/fs.nu`; uusi `nurl_write_file_safe path content "w"` runtime-kutsu — atominen open/write/close, palauttaa 0/-1 + errno)
- [x] `append_file path content` → `! v IoErr` (sama runtime, mode `"a"`)
- [x] `file_exists path` → `b` (RT — `nurl_file_exists`)
- [x] `file_size path` → `! i IoErr` (`stdlib/std/fs.nu`; käärii `nurl_file_size`:n -1-konvention IoErr:ksi)
- [x] `file_delete path` → `! v IoErr` (`stdlib/std/fs.nu`; jos tiedostoa ei ole, palauttaa `NotFound` koska `remove` ei aja errno:a luotettavasti)
- [x] `dir_create path` (`stdlib/std/fs.nu`; uusi `nurl_dir_create` runtime — `mkdir(path, 0755)` + errno; `dir_create_all` myöhemmin)
- [x] `dir_list path` → `! ( Vec String ) IoErr` (`stdlib/std/fs.nu`, 2026-04-28; runtime §13 `nurl_dir_list_open/next/close` — POSIX `opendir/readdir`, Win32 `FindFirstFileA/FindNextFileA`. Suodattaa "." ja ".." automaattisesti. Järjestys host-määrittelevä; sortteeraa `sort_by cmp_string` jos tarvitset deterministisen järjestyksen. Testi: `compiler/tests/fs_dir_list.nu`.)
- [x] `dir_remove path` (`stdlib/std/fs.nu`; uusi `nurl_dir_remove` runtime — `rmdir(path)` + errno; rekursiivinen variantti myöhemmin)
- [x] `path_join a b`, `path_basename`, `path_dirname`, `path_extension` (`stdlib/std/path.nu`, 2026-04-28). Hyväksyy sekä `/` että `\\` -erotinta sisään, tulostaa aina `/`-erottimella. Drive-letter prefix (`C:`) tunnistetaan absoluuttiseksi. Argumenttityyppi raaka `s` → kirjoita literaali suoraan tai välitä `( string_data str )`. Testi: `compiler/tests/path_basic.nu`.
- [x] `path_is_absolute`, `path_normalize` (`stdlib/std/path.nu`, 2026-04-28). `path_normalize` collapsee `.`, `..` ja kaksoiserottimet; `..` juuren yli pudotetaan hiljaisesti.
- [x] File handles: `file_open`, `file_close`, `file_write` (RT)
- [x] Bufferoitu streaming-luku — `stdlib/std/bufio.nu` (`BufReader`), 2026-05-21.
      Korvaa `file_read_chunk` / `file_readline` -aikeet: streaming-rivinluku
      tiedostosta tai stdinistä lataamatta koko sisältöä (vrt. `read_file` /
      `csv_reader_new` jotka lataavat kerralla). 64 KiB puskuri, `fread` per
      refill, `memchr`-rivinjako. `bufreader_open` / `bufreader_stdin` /
      `bufreader_read_line` (owned `?String`) / `bufreader_read_line_into`
      (uudelleenkäytä caller-String → zero-alloc ETL-silmukka) / `bufreader_eof`
      / `bufreader_close`. Puhdas-NURL `& \`c\``-FFI (fread/memchr/memmove/
      fdopen), ei runtime.c-muutoksia. Tukifunktio `string_push_bytes`
      (`stdlib/core/string.nu`). Testit: `compiler/tests/bufio_basic.nu` +
      `bufio_stream.nu` (50001 riviä, chunk-rajat + puskurin kasvu; ASan/
      UBSan/leak puhdas).

### 7. `hashmap` — geneerinen hash-kartta
Nykyinen `nurl_map_*` on rajoittunut (string→i64).
- [x] String→i64 -spesialisoitu kartta (RT) — pidetään bootstrapia varten
- [x] `HashMap[K V]` geneerinen (`stdlib/std/hashmap.nu`) — open addressing + linear probing, opaque handle `HashMap [K V] { s ctl }` 48 B kontrolliblokin (`{keys*, vals*, states*, len, cap, tombstones}`) yli. Cap aina pow-of-2, resize ≥75% load factorilla. API: `map_new/with_cap/len/cap/is_empty/get/set/remove/contains/each/fold/free`. Hash + eq välitetään closurena per-call (ei type-class-dispatchia); stock-funktiot `hash_string/eq_string/hash_int/eq_int` valmiina samassa tiedostossa. Testi: `compiler/tests/hashmap_generic.nu` (HashMap[s i] wordcount + resize, HashMap[i s] inverse).
- [x] `map_iter` — palauttaa `( Pair K V )` parit laiska iteraattorina
      (`stdlib/std/hashmap.nu`, 2026-04-28). Borrows the map; cmd=1 frees
      8-byte walk-state buffer. Pari-kentät bitwise-kopio slotin
      sisällöstä (sama trivial-only-rajoitus kuin `map_keys`/`map_values`).
      Testi: `compiler/tests/hashmap_iter.nu` (HashMap[s i] sum/count +
      sortattu key-listaus + abandon mid-walk + empty-map).
- [x] `map_keys`, `map_values` (NURL, palauttaa `Vec[K]` / `Vec[V]`; bitwise-
      kopio, sama trivial-only-rajoitus kuin `vec_map`:lla; järjestys host-
      määrittelevä — sortteeraa jos tarvitset deterministisen järjestyksen.
      Testi: `compiler/tests/hashmap_keys_values.nu`, 2026-04-28)
- [x] `map_clone` / `map_clone_with` (`stdlib/std/hashmap.nu`, 2026-05-21).
      Säilyttävät lähteen slot-layoutin verbatim → ei rehashia, kloonin haut
      käyttäytyvät identtisesti. `map_clone` = bitwise (triviaalit K/V);
      `map_clone_with [K V] m ( @ K K ) clone_k ( @ V V ) clone_v` = syväkopio.
      Testi: `compiler/tests/clone_basic.nu`.

### 8. `int` ja `float` — numeeriset operaatiot
- [x] `int_to_string` (RT — `nurl_str_int`)
- [x] `int_from_string` (RT — `nurl_str_to_int`, ei virhe-erottelua)
- [x] `float_to_string` (RT — `nurl_str_float`)
- [x] `float_parse` → `! f ParseErr` (`stdlib/std/float.nu`, 2026-04-27 — `nurl_str_to_float_safe` strtod-pohja + sideband-arvo via `nurl_str_float_value`)
- [x] `int_abs`, `int_pow`, `int_sign`, `int_min_val` (`stdlib/std/int.nu`, 2026-04-27). `int_min`/`int_max`/`clamp_i` löytyvät jo `stdlib/std/cmp.nu`:sta (`min_i`/`max_i`/`clamp_i`).
- [x] `int_parse → ! i ParseErr` (`stdlib/std/int.nu`, 2026-04-28). Strict
      raw-`s`-parseri symmetrisesti `float_parse`:n kanssa: optionaalinen
      `+`/`-` etumerkki + 1+ desimaalia, ei trailing garbagea, ei whitespacea.
      Tyhjä input / pelkkä etumerkki → Empty, mikä tahansa ei-numero →
      BadFormat. Overflow ei vielä detektoidu (atoll wrappaa hiljaa) —
      myöhempi revisio voi lisätä Overflow-tunnistuksen. Testi:
      `compiler/tests/int_parse.nu`. Owned-`String`-puolelta käytä
      `stdlib/core/string.nu`:n `string_to_int`-funktiota.
- [x] `float_abs`, `float_floor`, `float_ceil`, `float_round`, `float_sqrt`, `float_pow` (`stdlib/std/float.nu`, 2026-04-27 — libm-sillat `nurl_fabs/floor/ceil/round/sqrt/pow`)
- [x] `float_sin`, `float_cos`, `float_tan`, `float_atan2`, `float_log`, `float_exp` (`stdlib/std/float.nu`, 2026-04-27 — libm-sillat)
- [x] `float_is_nan`, `float_is_inf` (`stdlib/std/float.nu`, 2026-04-27 — `nurl_is_nan`/`nurl_is_inf`. NURL:n `!=` on `fcmp one` joten `x != x` ei tunnista NaN:ia → tarvittiin runtime-helperit)
- [x] Vakiot: `INT_MAX`, `PI`, `E`, `TAU`, `PI_2`, `SQRT_2`, `LN_2`, `LN_10` (`stdlib/std/int.nu` + `float.nu`). `INT_MIN` ei mahdu literaalina (`-N` on `- 0 N` ja N ei mahdu i64:een) → tarjotaan funktiona `int_min_val`.
- **Kääntäjälaajennus 2026-04-27:** `! T E`-konstruktorin payload tukee nyt myös `f` (double) → bitcast double↔i64 i64-payload-slottiin (`gen_agg_lit` + `gen_match`'s `did_reconstruct` haaratus). Tämä mahdollisti `float_parse → ! f ParseErr`:n.
- Testi: `compiler/tests/math_basic.nu` (int_abs/pow/sign + INT_MAX/MIN + sqrt/pow/exp/log/sin/cos/tan/atan2/floor/ceil/round + NaN/Inf-predikaatit + float_parse hit/empty/garbage/exp).

### 9. `iter` — iteraatio-abstraktio
- [x] **Closure-pohjainen `( Iter A ) ≡ (@ ? A)` -edustus** (`stdlib/std/iter.nu`, MVP 2026-04-27). Ei trait-pohjainen `Iterator[T]` (NURL ei tue type-class-dispatchia geneeristen funktioiden läpi); sulkeuma joka tuottaa `? A`:n on käytännöllinen vastine.
- [x] `iter_map f`, `iter_filter pred`, `iter_fold init f`, `iter_collect` → `( Vec A )`
- [x] `iter_take n`, `iter_skip n`, `iter_chain a b`
- [x] `iter_zip other` ja `iter_enumerate` (`stdlib/std/iter.nu`,
      2026-04-28). Tukeutuvat uuteen `Pair[A B]`-tyyppiin
      (`stdlib/core/pair.nu`); `iter_zip` ei alloita omaa tilaa, cmd=1
      cascade molempiin lähteisiin. `iter_enumerate` 8-byte counter
      cmd=1-vapautuksella. Testi: `compiler/tests/iter_zip_enum.nu`.
- [x] `iter_count`, `iter_sum_i` (Iter[i]:lle), `iter_any/all/find pred`, `iter_each f`
- [ ] `iter_min/max [A] cmp` — voitaisiin lisätä kun käytäntöä syntyy; nyt `iter_fold` + `cmp_int`
- [x] `range from to`, `range_step from to step` (eager Vec-versiot säilyvät) + uudet `iter_range`/`iter_range_step` (laiskat) + `iter_repeat`/`iter_from_vec`
- **Auto-drop (2026-04-27):** edustus muutettu `(@ ? A)` → `(@ ? A i)` (yksi sulkeuma joka ottaa cmd-argumentin: 0=advance, 1=release state + cascade upstream). Kuluttajat kutsuvat `( src 1 )` lopussa, joten state-puskurit eivät vuoda. **Skaalauslupaus pidätty:** 1M alkion pipelinen vuoto = 192 B / 6 allokaatiota = sama kuin 5 alkion pipelinellä. Vuoto ei skaalaudu datan koon mukaan, vain pipelinen rakenteen (closure-env/per-stage). Manuaalinen `( iter_free [A] src )` keskeytysten varalta.
- Testi: `compiler/tests/iter_chain.nu` (24 case + 1M-alkion skaalaustesti, ASan vahvistaa: vain konstantti closure-env-overhead, ei state-vuotoja).
- **Mahdollistaa funktionaalisen tyylin koodin.** LLM-ystävällinen koska yksi yhtenäinen rajapinta.

### 10. `cmp` ja `sort`
- [x] `cmp_int a b` → `i` (-1,0,1), `cmp_float a b`, `cmp_str a b`, `cmp_string a b` (`stdlib/std/cmp.nu`, MVP 2026-04-27). `cmp_str/cmp_string` käyttävät uutta runtime-helperia `nurl_str_cmp` (3-way `strcmp`-wrapper). NaN-kohtelu `cmp_float`:ssa: dokumentoitu rajoitus, NaN sortataan loppuun.
- [x] `sort_by [A] v cmp` → `v` (`stdlib/std/sort.nu`, MVP 2026-04-27). In-place quicksort + Lomuto-partitio + komparaattori-closure. `sort_by_key` toteutetaan käytännössä antamalla projisoiva komparaattori; erillistä konstruktoria ei tarvita NURL:n nykyisessä API:ssa. Testi: `compiler/tests/sort_cmp.nu` (asc/desc/by-key/empty/singleton/presorted/strings, ASan-puhdas).
- [x] `binary_search [A] v target cmp` → `? i` (`stdlib/std/sort.nu`, MVP 2026-04-27). Standardi puolitus, palauttaa minkä tahansa täsmäävän indeksin tai None. Edellyttää `v`:n olevan järjestetty samalla `cmp`:llä.
- [x] `min_i/max_i/clamp_i`, `min_f/max_f/clamp_f`, geneeriset `min_by/max_by/clamp_by [A]` (`stdlib/std/cmp.nu`, MVP 2026-04-27).

---

## Tier 2 — Modernit tarpeet (teksti, data, verkko)

Tähän asti NURL on käyttökelpoinen yleiskieli. Nämä tekevät siitä kilpailukykyisen modernien kielten kanssa.

### 11. `json` — JSON-parsija ja -serialisoija (`stdlib/ext/json.nu`, MVP 2026-04-26)
- [x] `Json` enum: `JNull | JBool b | JNum String | JStr String | JArr (Vec Json) | JObj (Vec Json)`. Numerot säilytetään raakatekstinä → ei tarkkuusongelmaa, ja `json_num_as_i / json_num_as_f` projisoivat tarvittaessa. JObj on alternating key-val Vec (tasaiset indeksit JStr-avaimet).
- [x] `json_parse s` → `! Json ParseErr` (rekursiivinen laskeva parseri JsonParser-tilalla, käsittelee null/bool/number/string/array/object + escape-merkit `\" \\ \/ \n \t \r \b \f`. Virheet Empty / BadFormat / TrailingGarbage.)
- [x] `json_stringify j` → `String` (kompaktimuoto; symmetrinen escape-taulu).
- [x] `json_free j` (rekursiivinen vapautus; nojaa `vec_free_with` + `string_free`).
- [x] Konstruktorit + predikaatit: `json_null/bool/num_lit/str_lit/arr/obj`, `json_is_*`, `json_type_name`.
- [x] Convenience-konstruktorit: `json_int n`, `json_float x` (primitive → JNum), `json_arr_new`, `json_obj_new` (tyhjät kontainerit yhdellä kutsulla).
- [x] Accessorit: `json_arr_len/get`, `json_obj_get/has`, `json_num_as_i/as_f`, `json_str_data`, `json_bool_val`.
- [x] `json_pretty j` → `String` (2-välilyönnin sisennys; tyhjät `[]`/`{}` pysyvät yhdellä rivillä, JS:n `JSON.stringify(x, null, 2)` -semantiikalla).
- [x] `json_obj_keys j` → `( Vec String )` (fresh owned -kopiot avaimista; tyhjä Vec ei-objekteille).
- [x] `json_arr_each j f` / `json_obj_each j f` (closure-pohjainen iteraatio; `f : (@ v Json)` arrayille, `f : (@ v s Json)` objekteille jossa avain raakana `i8*`).
- [x] **Mutaatiot:** `json_arr_push j elem` → `b`, `json_obj_set j key val` → `b`. JArr/JObj:n sisempi `Vec[Json]` on heap-handle, joten mutaatio kohdistuu samaan dataan kaikkien handlejen läpi. Konsumoivat `elem`/`val`-omistajuuden, palauttavat F kun `j` on väärä variantti (silloin EI konsumoi). `json_obj_set` korvaa olemassaolevan avaimen (vapauttaa vanhan arvon) tai lisää uuden parin loppuun.
- [x] `json_clone j` → `Json` — rekursiivinen syväkopio.
- [x] `json_eq a b` → `b` — strukturoitu yhtäsuuruus. JNum vertaillaan **byte-exact** raakatekstinä (`1.0` ≠ `1.00`); JObj on järjestysriippuvainen (Vec-pohja). Numeeriseen vertailuun projisoi `json_num_as_f` molemmilta puolilta.
- [x] `json_get j path` → `? Json` — pisteerotettu path-syntax (`"user.items.0.name"`). Numeerinen segmentti = array-indeksi, muuten objekti-avain. Tyhjä path → koko j. None ensimmäisellä puuttuvalla segmentillä / tyyppivirheellä / out-of-range-indeksillä. **Lainattu** Json — älä vapauta erikseen.
- **Vaati kääntäjälaajennuksia:** `! T E`-payloadiin laajennettu tuki struct-handlejen (`! String IoErr`) JA leveiden enumien (`! Json ParseErr`) heap-boxauksen kautta — ks. `feedback_nurl_compiler_quirks.md`. Testi: `compiler/tests/json_basic.nu` (17 case: parse + stringify + pretty + each + obj_keys + build/mutate + path/get + clone/eq + virhepolut) + `json_recursive_proof.nu`. **Täysin NURL:ssa. Kriittinen LLM-koodille.**

### 12. `time` — aika ja päivämäärä
- [x] `now_ms` → `i` (`stdlib/std/time.nu`, 2026-04-27 — `nurl_now_ms` / `clock_gettime(CLOCK_REALTIME)`)
- [x] `now_seconds` → `i` (`stdlib/std/time.nu`, 2026-04-27)
- [x] `monotonic_ns` → `i` (`stdlib/std/time.nu`, 2026-04-27 — `CLOCK_MONOTONIC`, fallback REALTIME jos ei tuettu)
- [x] `sleep_ms ms` (`stdlib/std/time.nu`, 2026-04-27 — `nanosleep` Linuxilla, `Sleep` Windowsilla; signaalisuojattu retry-silmukka EINTR:lle)
- [x] `elapsed_ms_since t0` → `i` (`stdlib/std/time.nu`, 2026-04-27 — convenience benchmark-helper)
- [ ] `Time { i year, i month, i day, i hour, i min, i sec, i ns }` (NURL)
- [ ] `time_from_unix t` → `Time` (NURL — laske NURL:ssa)
- [ ] `time_format t fmt` → `String` (NURL, fmt-pattern käsin)
- [ ] `time_parse s fmt` → `! Time ParseErr` (NURL)
- Testi: `compiler/tests/time_basic.nu` (8 invarianttia — kaikki epädeterministiset arvot maskataan totuusarvoiksi: positiivisuus, monotonic-järjestys, sleep ≥ 30 ms, no-op nollasleep).

### 13. `regex` — säännölliset lausekkeet (`stdlib/ext/regex.nu`, MVP 2026-04-28)
- [x] `regex_compile pattern` → `! Regex ParseErr` (NURL — Thompson NFA-konstruktio)
- [x] `regex_test r text` → `b` (mikä tahansa esiintymä)
- [x] `regex_match r text` → `b` (koko teksti täsmää)
- [x] `regex_find r text` → `? Match` (vasemmanpuoleisin)
- [x] `regex_find_all r text` → `( Vec Match )` (ei-päällekkäiset)
- [x] `regex_replace r text repl` → `String`
- [x] `regex_split r text` → `( Vec String )`
- [x] `regex_free r` → `v`
- **Pattern-tuki:** literal, `.`, `*`/`+`/`?`, `[abc]`/`[a-z]`/`[^...]`, `^`/`$`, `|`, `(...)`, escapes `\.\*\+\?\(\)\[\]\|\^\$\\\/` + `\n\t\r\f\v\0` + built-in classes `\d\D\w\W\s\S` (`\w` = `[A-Za-z0-9_]`, `\s` = space/tab/cr/lf).
- **Algoritmi:** O(n × m) NFA-simulointi (text length × NFA size) — ei backtrackingiä, ei katastrofaalista räjähdystä. Set-pohjainen (kaksi state-set bufferia + dedupe via parallel marked-vektori).
- **Suunnittelupäätös:** Regex-handle on opaque pointer (`{ s ctl }` heap-allocated `RegexImpl`:iin) jotta mahtuu `! Regex ParseErr`:n kapean enumin tag-fold-payload-i64-slottiin. Greedy-quanttorit, ei capture-ryhmiä, ei backreferencejä, ei lookaround:ia — determinismi tärkeämpi kuin ominaisuusrunsaus.
- **Match-rakenne:** `Match { i start, i len }` — half-open span alkuperäiseen tekstiin. Tyhjät matchit ohitetaan find_all/split/replace-funktioissa silmukoiden katkaisemiseksi.
- Testi: `compiler/tests/regex_basic.nu` (kvanttorit, anchors, classes, alternaation, find_all, replace, split + virhepolut).
- **Täysin NURL:ssa.** Yksinkertainen NFA-pohjainen, ei PCRE-kompleksisuutta. **Determinismi tärkeämpi kuin ominaisuusrunsaus.**

### 14. `http` — HTTP-asiakas (server tier 3:een)
- [x] **MVP (placeholder, jatkokehitys jatkuu)** (`stdlib/ext/http.nu`,
      runtime §14, 2026-04-28). libcurl-bridge synkronisilla `GET` ja
      `POST` -kutsuilla; PUT/DELETE/PATCH C-puolelta jo tuettu mutta
      NURL-pinta vielä auki.
- [x] `http_get s url` → `! Response HttpErr`
- [x] `http_post s url s body s content_type` → `! Response HttpErr`
      (content_type `` ohittaa headerin)
- [x] `Response { s raw }` opaque-handle runtime-ownettuun
      `NurlHttpResponse`-rakenteeseen; `http_status/http_body_str/
      http_header_count/http_header_name/http_header_value` accessorit
      borrow-näkymin ja `response_free` cascade-vapautus.
- [x] `Header { String name String value }` + `header_new`/`header_free`
      (request-puolen wrapper, ei vielä konsumoitu MVP:ssä).
- [x] `HttpErr` enum: `HttpConnect|HttpTimeout|HttpTls|HttpDns|
      HttpInvalidUrl|HttpOther` (prefiksoitu välttämään törmäys
      `IoErr`:n `Other/NotFound`-varianttien kanssa flat-namespacessa).
- [x] **Build-pipeline:** `build.sh` (`--no-tests` ohittaa testit
      Docker-imagessa), `nurl.sh`, `compiler/tests/run_tests.sh`
      detektoivat libcurlin pkg-configilla; merkkitiedosto
      `stdlib/runtime.curl` ohjaa linkkausta `-lcurl`.
      Ilman libcurlia symbolit yhä resolvoituvat ja palauttavat
      `HttpOther`. **Linux-kontti** (`api/Dockerfile`) saa
      `libcurl4-openssl-dev` + `pkg-config` molempiin vaiheisiin.
      **Windows mingw-cross**: kontissa ei ole vielä Windows-libcurlia,
      joten `runtime.win.o` käännetään ilman `-DNURL_HAVE_LIBCURL` →
      Windows-buildissa http-kutsut palauttavat `HttpOther`. **WASM**
      ei vaadi (selain-fetchille tehdään myöhemmin oma binding).
- [x] **Testi gateattu:** `compiler/tests/http_basic.nu` ajetaan vain
      kun `NURL_HTTP_TESTS=1`-ympäristömuuttuja on asetettu (default
      build ei riipu netistä; `http_*`-prefix-suodatin run_tests.sh:ssä).
      Manuaalinen ajo: `NURL_HTTP_TESTS=1 ./build.sh`.
- TLS automaattisesti libcurlin kautta (`CURLOPT_SSL_VERIFYPEER=1` default).
- Hardcoded MVP-rajat: `CURLOPT_TIMEOUT=30s`, `CURLOPT_CONNECTTIMEOUT=10s`,
  `CURLOPT_FOLLOWLOCATION=1`, `User-Agent: nurl-http/0.1`.

**Headers + verbs (2026-04-29):**
- [x] `http_request s method s url s body s headers_blob` — unified
      entry point. Headers passed as a UTF-8 CRLF-delimited blob
      (`"Authorization: Bearer xyz\r\nX-Trace: abc\r\n"`); empty `` ``
      sends none. Lines without a colon are silently dropped.
      Runtime `nurl_http_perform_full(url, method, body, headers_blob)`
      replaces `_simple` and parses the blob into either a
      `curl_slist` (libcurl) or a UTF-16 buffer for
      `WinHttpAddRequestHeaders` (WinHTTP).
- [x] `http_get_with_headers` / `http_post_with_headers` — convenience
      wrappers around `http_request` with pre-set verb. Both keep the
      MVP `content_type` argument on the POST variant for ergonomics;
      `__with_ct` prepends `Content-Type: …` to the user blob.
- [x] PUT / DELETE / PATCH NURL pinta (`http_put`, `http_delete`,
      `http_patch`) — delegates to `http_request` with the right verb.
      Runtime path was already wired up, only the wrapper was missing.
- [x] `header_blob_one s name s value → String` — convenience builder
      for one CRLF-terminated `"Name: Value\r\n"` line. Combine with
      `string_concat` when assembling multi-header blobs from typed
      pieces.
- [x] `http_err_name HttpErr e → s` — diagnostic helper that returns
      the variant name as a raw `s` (e.g. `"HttpDns"`).
- [x] Lexer: backtick strings now recognise `\r` (CR) in addition to
      `\n`, `\t`, `\\`. Required so user code can write CRLF-style
      headers as literals (`` `Authorization: Bearer x\r\n` ``).
      Grammar bumped to **v1.4**.
- [x] `http_post_json` / `http_put_json` — JSON convenience,
      `stdlib/ext/http_json.nu` (separate file so HTTP-only callers
      don't pull in `json.nu`). Serialises with `json_stringify` and
      sets `Content-Type: application/json`.

**Per-call timeouts shipped (2026-05-01):**
- [x] `http_request_to s method s url s body s headers_blob i timeout_ms i connect_timeout_ms → ! Response HttpErr` (`stdlib/ext/http.nu`). Pass 0 (or any non-positive value) to fall back to the runtime default of 30 000 ms total / 10 000 ms connect. Required for LLM clients (Anthropic / OpenAI) where a single request can take a minute or more, far longer than the MVP HTTP budget. Runtime: new `nurl_http_perform_full_to(url, method, body, headers, timeout_ms, connect_timeout_ms)` (libcurl `CURLOPT_TIMEOUT_MS` / `CURLOPT_CONNECTTIMEOUT_MS`; WinHTTP `WinHttpSetTimeouts` mapping); legacy `nurl_http_perform_full` survives as a thin wrapper with the historical 30 s / 10 s budget. Compiler `init_syms` registers both names.

**Continuation roadmap (jatkokehitys):**
- [ ] `HttpOptions` struct that bundles timeout, redirects, follow_count,
      verify_tls, user_agent overrides — keyword-arg-tyyppinen wrapper
      (per-call timeout shipped, this would generalise the pattern)
- [ ] Response.body_len käyttöön (zero-copy slaisilta `Vec[u8]`-muotoon
      kun bittitarkat tyypit shipataan)
- [ ] Streaming-vastaukset (`http_get_stream` joka palauttaa
      `( Iter Bytes )` callbackilla, vaatii cancellable-iter-mallin)
- [ ] Windows libcurl-bundle konttiin (`libcurl-x86_64-w64-mingw32`
      + `libcurl.dll.a`)
- [ ] HTTP-server (Tier 4 §25): erillinen riippuvuus, libcurl ei
      hoida server-puolta — civetweb / mongoose / suora socket.
- [ ] `Vec[Header]`-syöte `http_request`:lle kun `?Header`
      multi-field-struct heap-box on tuettu kääntäjässä (nyt blob-`s`
      on ainoa rajapinta).

### 15. `env` — ympäristömuuttujat ja CLI-argumentit (`stdlib/ext/env.nu`, MVP 2026-04-28)
- [x] `env_args` (RT — `nurl_argv_count`/`nurl_argv_get`; wrapperi NURL:ssa)
- [x] `env_exit code` (RT — `nurl_exit`)
- [x] `env_args_count`, `env_arg i`, `env_args_list` → `( Vec String )` (`stdlib/ext/env.nu`)
- [x] `env_get name` → `? String` (RT — `getenv`; runtime §13 `nurl_env_get`)
- [x] `env_set name value` → `! v IoErr` (RT — POSIX `setenv` / Win32 `_putenv_s`)
- [x] `env_unset name` → `! v IoErr` (RT — POSIX `unsetenv` / Win32 `_putenv_s` empty value)
- [x] `env_cwd` → `! String IoErr` (RT — POSIX `getcwd` / Win32 `_getcwd`)
- [x] `env_chdir path` → `! v IoErr` (RT — POSIX `chdir` / Win32 `_chdir`)
- [x] `env_var_or name default` → `String` (NURL)
- Testi: `compiler/tests/env_basic.nu` (argc, get/set/unset/var_or, chdir-virhe).

---

## Tier 3 — Erikoistuneet (riippuvat use casesta)

Nämä ovat tärkeitä mutta eivät kaikille käyttäjille. Voidaan toteuttaa rinnakkain tarpeen mukaan.

### 16. `process` — alaprosessien hallinta (`stdlib/std/process.nu`, MVP 2026-04-30)
- [x] `process_run s cmd ( Vec s ) args s stdin_str → ! Output ProcessErr` (NURL+RT — runtime §16). Synkroninen single-shot run, lukittuu kunnes child poistuu ja stdout+stderr on luettu kokonaan. Argumentti-Vec luetaan suoraan `vec_data`-pointterin kautta `char**`-muodossa, joten ei marshallointia. `stdin_str` syötetään verbatim child-prosessin stdiniin (`` = tyhjä). Output on `{ s raw }`-opaque-handle runtime-`NurlProcResult`-rakenteeseen — accessorit alla.
- [x] **Convenience-arities** — `process_run0 cmd`, `process_run1 cmd a0`, `process_run2 cmd a0 a1`, `process_run3 cmd a0 a1 a2`. Rakentavat Vec[s]:n itse + vapauttavat sen. `process_run_shell s sh_cmd → ! Output ProcessErr` ajaa `/bin/sh -c sh_cmd` (POSIX-only; Windows-ekvivalentti tulee myöhemmin).
- [x] **Accessorit (BORROWED views runtime-puskureihin):** `output_exit_code → i`, `output_stdout / output_stderr → s`, `output_stdout_len / output_stderr_len → i`, `output_success → b` (`exit_code == 0`), `output_free → v` (cascade-vapauttaa stdout+stderr-puskurit + Output-handlen). `process_err_name ProcessErr e → s` diagnostiikkaa varten.
- [x] **`Output { s raw }` opaque handle** (NURL — sama kuvio kuin `Response { s raw }` HTTP:ssa). Yhden kentän struct mahtuu `! Output ProcessErr`-tag-fold-payload-i64-slottiin ilman heap-boxausta.
- [x] **`ProcessErr` enum** (NURL — variantit prefiksoitu `Process*` jotta ei törmää `IoErr.NotFound`/`Other` flat-namespaceen): `ProcessNotFound | ProcessExecFailed | ProcessIo | ProcessOther`. Tagit synkkaa runtimen `NURL_PROC_ERR_*`-vakioiden kanssa (1-4).
- [x] **POSIX-backend** (Linux + macOS): `pipe(2)` × 4 (stdin / stdout / stderr / exec-error sideband), `fork(2)`, `execvp(3)`. CLOEXEC sideband-kirjoituspäässä → `read()` palauttaa EOF kun exec onnistuu, errno-arvon kun exec epäonnistuu. Stdout+stderr non-blocking + `poll(2)` → ei deadlock-vaaraa pitkillä output-streameilla. Stdin-kirjoitus blocking; SIGPIPE väliaikaisesti ignored. `WIFSIGNALED` mappaa signaali- exitin `128 + sig`-koodiksi (sama kuin shell).
- [x] **Win32-backend**: `CreateProcessA` + `CreatePipe` + reader-threads (`_beginthreadex`) stdout:lle ja stderr:lle. Argv-quotaus seuraa MSDN:n "Everyone quotes command line arguments the wrong way" (Daniel Colascione 2011) -säännöstöä — backslash-runs adjacent to `"` doublattu, koko arg:n ympäri lainausmerkit jos sisältää `space\t\n\v"`. PATH-haku CreateProcessAn `lpApplicationName=NULL`-polun kautta, joka käyttää `lpCommandLine`:n ensimmäistä tokenia.
- [x] **WASI / muut targetit**: `nurl_proc_run`-stubi palauttaa `ProcessOther`. wasm32-wasi-build kääntyy ja linkkaa puhtaasti.
- [x] **Memory model:** Output on yksittäinen heap-handle (`NurlProcResult` struct: 48 B + stdout-puskuri + stderr-puskuri). Caller MUST `output_free` Result-Ok-haarassa. ProcessErr-haara ei kanna handlea (runtime vapauttaa itse epäonnistuneella err_kind:llä). `output_stdout/stderr` ovat lainattuja `s`-näkymiä — kopioi `string_from`:lla jos tarvitset Output:n elinaikaa pidempään.
- [x] **Testi:** `compiler/tests/process_basic.nu` (8 case): `echo hello world`, `true`/`false` exit-koodit, `printf 1>&2; exit 7`-shellpipeline, `cat`-stdin-pipe, `sh -c "echo a; echo b"`-monirivinen output, missing-binary → `ProcessNotFound`, empty-cmd → `ProcessNotFound`. Bootstrap-kiintopiste säilyy. Käyttää bare-namejä (`echo`, `sh`, `cat`, `true`, `false`) joten tomi toimii joka POSIX-hostissa execvp-PATH-haun kautta.
- [x] **Kääntäjälaajennus:** `init_syms` rekisteröi 8 uutta `nurl_proc_*`-runtime-funktiota palautustyypeineen (`compiler/nurlc.nu`). Python-bootstrap (`compiler/src/llvm_gen.py`) ei tarvitse lisäystä koska `nurlc.nu` ei kutsu prosessi-API:a.
- **MVP-rajoitteet** (jatkokehitys jätetty alle):
- [ ] Per-call timeout / cancellation (`HttpOptions`-tyyliset wrapperit)
- [ ] Streaming stdout/stderr (nyt täysi puskurointi → ei sovi gigatavuluokan outputille)
- [ ] Env-overridet child-prosessille (`process_run_with_env`)
- [ ] Cwd-override child-prosessille
- [ ] `process_spawn` async-handle (vaatii cancellable-iter-mallin tai threadit)
- [ ] Shell-wrapper Windows-puolelle (`cmd /c` POSIX-`/bin/sh`:n rinnalle)
- **LLM-agenttihostingin keystone.** Yhdessä `http`/`fs`/`env`/`json`/`fmt`/`log`-kirjastojen kanssa NURL voi nyt ajaa oikeita agenttipipelinejä — `git`, `npm`, `pytest`, `cargo`, `rg` jne. Synkroninen MVP riittää 95% LLM-tool-call-käytöstä.

### 17. `net` — TCP/UDP-socketit
- [ ] `tcp_connect host port` → `! Conn IoErr` (RT — socket/connect)
- [ ] `tcp_listen port` → `! Listener IoErr` (RT — bind/listen/accept)
- [ ] `udp_socket port` → `! Socket IoErr` (RT)
- [ ] Buffered IO: `BufReader`, `BufWriter` (NURL, runtime-fd:n päälle)
- [ ] `dns_resolve hostname` (RT — `getaddrinfo`)

### 18. `crypto` — kryptografia (`stdlib/std/hash.nu` + `stdlib/std/encode.nu` + `stdlib/std/random.nu`, MVP 2026-04-30)
- [x] **`sha256_hex s` → `String`** (`stdlib/std/hash.nu`, runtime §17). Self-contained FIPS 180-4 toteutus runtime.c:ssä — ei libsodium/openssl-linkkausdiriippuvuutta. Heap-owned 64-merkkinen lowercase hex digest. Validoidaan `compiler/tests/crypto_basic.nu`-vektoreilla (`""`, `"abc"`, 56-byte block-edge case).
- [x] **`hmac_sha256_hex key msg` → `String`** (`stdlib/std/hash.nu`, runtime §17). Standard HMAC-konstruktio (RFC 2104) SHA-256:n päällä. NUL-terminoidut input-stringit; webhook-allekirjoitusten verifiointiin (GitHub, Stripe, Slack) ja Bearer-token-payloadien tarkistukseen. Avain-blob > 64 B esi-hashetaan SHA-256:lla.
- [x] **Base64-koodaus** (`stdlib/std/encode.nu`, RFC 4648). `b64_encode s → String` standardi-aakkosto + padding, `b64_url_encode` URL-safe (`- _`, ei paddingia), `b64_decode → ! String ParseErr` ja `b64_url_decode` ohittavat ASCII-whitespacen, palauttaa `BadFormat` huonosta merkistä, `TrailingGarbage` non-padding-merkille `=`:n jälkeen. Round-trip pidetty kaikilla RFC §10-vektoreilla.
- [x] **Hex-koodaus** (`stdlib/std/encode.nu`). `hex_encode s → String` lowercase 2 chars/byte, `hex_decode → ! String ParseErr` hyväksyy upper- ja lowercasen, virhetilat `Empty`/`BadFormat`. Hyödyllinen content-addressing-vertailuihin ja bin↔hex-roundtrippeihin.
- [x] **Secure random** (`stdlib/std/random.nu`, runtime §17). Linux: `getrandom(2)` → fallback `/dev/urandom`; macOS: `arc4random_buf`; Windows: `BCryptGenRandom`. **Rajapinta:** `rand_u64 → i` (full-range signed 64-bit), `rand_range from to → i` (uniform [from,to), rejection-sampled niin että ei biasia), `rand_hex_str n → String` (2*n lowercase hex-merkkiä `n` random-tavusta; `n` clampattu [0, 4096]).
- [ ] Lisähashit: `sha512`, `blake3`, `md5` (RT — libsodium-FFI tai oma toteutus jos koko sallii)
- [ ] HMAC-perheen laajennus (`hmac_sha512`) kun bittitarkat tyypit + bytes shipataan
- [x] Random: `rand_u64`, `rand_range from to`, `rand_hex_str n` (RT — `getrandom`/`arc4random_buf`/`BCryptGenRandom`, 2026-04-30)
- [x] Base64 encoding/decoding standard + URL-safe (NURL, RFC 4648, 2026-04-30)
- [x] Hex encoding/decoding (NURL, 2026-04-30)
- **MVP-päätös:** SHA-256 ja HMAC-SHA-256 toteutettu suoraan runtime.c:ssä public-domain-pohjalla (FIPS 180-4 + RFC 2104). Tämä karsii libsodium/openssl-build-riippuvuuden ja pitää WASM-buildin puhtaana. SHA-512/BLAKE3/HMAC-SHA-512 myöhemmin libsodium-FFI:n kautta jos bytes-tyyppi + binary-buffer-API on saatavilla.

### 19. `set` — joukot
- [x] `Set[E]` — direct open-addressing impl (`stdlib/std/set.nu`, MVP 2026-04-26)
- [x] `set_new/with_cap/add/remove/contains/len/cap/is_empty/each/fold/free/free_with` (NURL)
- [ ] `set_union`, `set_intersect`, `set_diff` (NURL)

### 20. `log` — strukturoitu lokitus
- [x] `log_info msg`, `log_warn msg`, `log_error msg`, `log_debug msg` (`stdlib/std/log.nu`, MVP 2026-04-30 — kaikki stderr:lle, kiinteä tag-prefiksi `[INFO]  /[WARN]  /[ERROR] /[DEBUG] `).
- [x] `log_set_level level` / `log_get_level` (`stdlib/std/log.nu`, runtime §15 mutable `g_log_level` — process-wide globaali. Vakiotehtaat `log_level_debug/info/warn/error/off → i` koska module-level `: i FOO` hyväksyy vain literaali-RHS:n.)
- [x] **Formaattiset varianteit**: `log_debugf1/2/3`, `log_infof1/2/3`, `log_warnf1/2/3`, `log_errorf1/2/3` — `{}`-substituutio `stdlib/std/fmt.nu`:n päältä, raaka-`s`-argumentit (literal / `string_data` / `nurl_str_int`). Below-threshold-kutsut allokoivat silti pienen Vec[s]:n marshallointia varten — Debug-suppressed hot path -kutsuissa gateaa itse `( log_get_level )`:llä.
- [ ] Strukturoitu data: `log_info_kv` (NURL) — myöhempi, jätetty JSON-puolen jälkeen
- [ ] JSON-output (NURL, `json`:in päälle) — suora `log_info_json j` vasta kun structured-data API on lukittu

### 21. `path` — polkujen käsittely (laajempi kuin `fs`:ssä)
- [ ] `Path { String inner }` — tyypitetty polku (NURL)
- [ ] `path_normalize`, `path_canonical`, `path_relative_to base` (NURL; canonical vaatii RT:tä `realpath`)
- [ ] `path_is_absolute`, `path_is_relative` (NURL)
- [ ] Cross-platform path separators (NURL, compile-time flagi)

### 22. `bytes` — byte buffers (`stdlib/std/bytes.nu`, MVP 2026-05-01)
**Pohja:** `( Vec u )` on kanonista byte-puskuria. **Kaikki Vec[A]-operaatiot** (push/pop/get/set/len/cap/data/clear/extend/each/fold/free) toimivat suoraan `[u]`-instantioinnilla — bytes.nu lisää vain byte-spesifiset helperit joita generic Vec ei voi tarjota.
- [x] `bytes_from_str raw → ( Vec u )` — copy NUL-terminated string (NUL excluded); for owned String pass `( string_data str )`.
- [x] `bytes_to_str ( Vec u ) v → String` — copy bytes into String. NUL-bytes inside `v` säilyvät verbatim mutta `string_data` palauttaa ensimmäiseen NULiin asti — itera käsin jos tarvitset koko sisällön.
- [x] `bytes_extend_str ( Vec u ) v s raw → v` — append from NUL string.
- [x] `bytes_to_hex ( Vec u ) v → String` — lowercase 2 chars/byte (sama formaatti kuin `hex_encode` `stdlib/std/encode.nu`:ssa).
- [x] `bytes_from_hex s raw → ! ( Vec u ) ParseErr` — symmetrinen decoder (`Empty`/`BadFormat`).
- [x] `bytes_eq ( Vec u ) a ( Vec u ) b → b` — byte-by-byte equality, length-fast-path.
- [x] `bytes_find_byte ( Vec u ) v u target → ? i` — first occurrence.
- [x] `bytes_index_of ( Vec u ) v ( Vec u ) needle → ? i` — naive O(n × m) substring search; empty needle → `Some 0` (mirrors `string_index_of`).
- [x] `bytes_starts_with ( Vec u ) v ( Vec u ) prefix → b`, `bytes_ends_with ( Vec u ) v ( Vec u ) suffix → b` — prefix/suffix detection for binary protocol magic bytes (PNG, ZIP, …).
- [x] `bytes_slice ( Vec u ) v i from i to → ( Vec u )` — copy of the half-open range `[from, to)`; both bounds clamped to `[0, len]`, inverted/empty range → empty Vec[u]. Caller owns the result.
- [x] **Binary-IO** (`stdlib/std/fs.nu`): `read_file_bytes path → ! ( Vec u ) IoErr`, `write_file_bytes path v → ! v IoErr`, `append_file_bytes path v → ! v IoErr`. NUL-tavut säilyvät, jolloin tämä on oikea API kuville/arkistoille/msgpackille.
- [x] **Runtime §4 -laajennus:** `nurl_read_file_bytes(path)` palauttaa heap-puskurin + sideband-pituus `nurl_last_bytes_len()`. `nurl_write_file_bytes(path, data, len, mode)` writeaa "wb"/"ab".
- [ ] Endianness-muunnokset (`bytes_read_u8/u16_be/u16_le/u32_be/u32_le/u64_be/u64_le buf i`) — tulevat kun `u16`/`u32`/`u64`-tyypit shipataan multi-char TYPE_KW-tokeneiksi
- [ ] Zero-copy slice-näkymä — vaatisi `BytesView { *u ptr, i len }` -tyypin Vec[u]:n päälle; jätetty kun caller-pattern on `bytes_slice` + `vec_free`
- **Suunnittelupäätös:** Bytes ei ole oma struct vaan pelkkä convention layer Vec[u]:n päällä. Tämä pitää nimiavaruuden pienenä (vec_*-perhe käytettävissä) ja on linjassa "yksi tapa tehdä asia" -periaatteen kanssa. Endianness-muunnokset jäävät myöhempään koska ne tarvitsevat sized-unsigned-tyypit (u16/u32/u64).

### 23. `arena` — bulk-free bumpparikko (`stdlib/std/arena.nu`, 2026-05-17)
Tarvitaan kun single-owner + auto-drop ei riitä: parseri/AST/regex-NFA jossa
allokoit tuhansia lyhytikäisiä solmuja ja haluat vapauttaa ne yhdellä kutsulla.
- [x] `Arena { s ctl }` opaque-handle, taustalla `ArenaImpl { *u data, i used, i cap }` (yksi puskuri). Linkitetty lista blokkeja jäi v2-työksi (säilyttäisi pointterit aktiivisina growthissa).
- [x] `arena_new` (cap=0), `arena_with_cap n` (preallokoitu)
- [x] `arena_alloc a n → *u` — 8-byte-aligned bump, NULL OOM:ssa (kutsuja tarkistaa)
- [x] `arena_alloc_aligned a n align → *u` — SIMD / byte-tight kasit (power-of-two alignment)
- [x] `arena_used a / arena_cap a / arena_remaining a` — introspect
- [x] `arena_reset a` — nollaa käyttö, säilytä puskuri (mitätöi kaikki ulkonaolevat pointterit)
- [x] `arena_free a` — vapauta puskuri + handle
- [ ] *(v2)* `arena_alloc_n [T] a count → *T` — tyypitetty wrapper
- [ ] *(v2)* Chained-chunk arena — linkitetty lista blokkeja growthia varten

### 24. `fmt` — string-formatointi (`stdlib/std/fmt.nu`, MVP 2026-04-30)
- [x] `fmt tmpl ( Vec s ) args → String` — runtime-arity entry point, `{}` substituoi seuraavan argumentin vasemmalta oikealle. `{{` / `}}` escaping, surplus-args silently dropped, missing-args emit literal `{}` jotta bugi näkyy.
- [x] Convenience-arities: `fmt1/2/3/4`, `println_fmt1/2/3/4` (build → stdout + `\n` → free), `eprintln_fmt1/2/3/4`. Argumentit ovat raakoja `s` (i8*) — string-literaalit toimivat suoraan; `String`:lle välitä `( string_data str )`, `i`:lle `( nurl_str_int n )`, `f`:lle `( nurl_str_float x )`.
- [x] Token-tehokas: `( println_fmt2 \`{} = {}\` \`answer\` \`42\` )` säästää 4–5x verrattuna manuaaliseen `nurl_str_cat3` -ketjuun.
- **Suunnittelupäätös:** raaka-`s`-argumentit (ei type-class-dispatchia) jotta kääntäjä-monomorfisaation kanssa ei tule törmäyksiä. Type-checked formatting jätetään kun trait-pohjainen `Display[A]` on luotu — nyt LLM-koodi konvertoi itse `nurl_str_int`:llä, mikä on yksiselitteistä ja näkyy diff-tasolla.
- Testi: `compiler/tests/fmt_basic.nu` (substituutio, escape, missing/surplus, dynamic-arity, empty template, owned String + integer mix, stderr).

---

## Tier 4 — Server-side ja edistyneet (kun kieli on vakiintunut)

Nämä eivät ole pakollisia kielen käyttökelpoisuudelle, mutta tekevät siitä tuotantokelpoisen.

### 25. `http_server` — HTTP-palvelinkehys (`stdlib/ext/http_server.nu` MVP 2026-05-02 + `http_router.nu` Phase 6 2026-05-05)
HTTP_SERVER_PLAN.md ohjaa toteutusta vaiheittain. Phase 1–4 + Phase 6 valmiit; Phase 5 (säikeistys) ja Phase 7–8 (conveniences + hardening) kesken.
- [x] **Phase 1: TCP-runtime** (`stdlib/std/net.nu` + `stdlib/runtime.c §18`, 2026-05-02) — `tcp_listen/_accept/_read_chunk/_write_all/_close`, `NetErr`-enum, POSIX/Win32-portatiivisuus, `tcp_set_timeout`, `tcp_peer_addr`. WASI-stubit.
- [x] **Phase 2: HTTP/1.1-pyyntöparseri** (`stdlib/ext/http_request.nu`, 2026-05-02) — `parse_request_head ( Vec u ) → ParsedHead` (tagged-struct-workaround multi-field-Result-Ok-aukolle), `HttpRequest { method, path, query, version, headers, body }`, `header_get` case-insensitive, `parse_url`, `parse_query`, `percent_decode/encode`, `read_body` Content-Length + Transfer-Encoding: chunked.
- [x] **Phase 3: HTTP/1.1-vastauskirjoittaja** (`stdlib/ext/http_response.nu`, 2026-05-02) — `HttpResponse { status, headers, body }`, `response_text/json/redirect/status_only/error`, `response_serialize` auto-Content-Length, `status_reason` 35+ koodia RFC 7231:n mukaan, chunked-streaming primitiivit (`response_begin_chunked` / `_write_chunk` / `_end_chunked`) SSE:lle.
- [x] **Phase 4: Single-threaded server** (`stdlib/ext/http_server.nu`, 2026-05-02) — `HttpServer { TcpListener, ( @ HttpResponse HttpRequest ) handler }`, `server_new/run_once/run/stop`. Sekvenssimäinen: yksi accept → parse → dispatch → write → close. 4xx/5xx-virheet stockit.
- [x] **Phase 6: Routing + middleware** (`stdlib/ext/http_router.nu`, 2026-05-05) — `Router { ( Vec Route ) routes }`, `Params { ( Vec QueryPair ) entries }`, `router_new/_free`, `router_get/_post/_put/_patch/_delete`, `router_any` (`"*"`-method), `router_handle Router HttpRequest → HttpResponse` (linear scan, first-match wins, 404 fallback). **Pattern-syntaksi:** `:name` capture (yksi segmentti, ei `/`), `*name` tail wildcard (loput polusta inc. `/`-merkit). `params_get` mirrors `header_get`:n `? String`-OWNED-copy-konvention. **Middleware** handler-wrapping-kombinaattoreina (ei `Vec[Middleware]`-rekisteriä, joka törmäisi multi-field closure-shaped-struct miscompiletukseen): `with_log_requests` (logs stderriin), `with_cors_default` (permissive CORS + OPTIONS preflight 204). Komposit closure-capturella `with_log_requests (with_cors_default base)`. Testi `compiler/tests/http_router.nu` (unconditional, ei socket): 14 dispatch-keissiä + params + middleware. Bootstrap-kiintopiste säilyy.
- **Strateginen virstanpylväs saavutettu:** MCP HTTP/SSE transport (§33:n jäljellä oleva work) ei enää blokkaa mihinkään stdlib-aukkoon — Phase 3.3:n chunked-streaming + Phase 6:n routing antavat kaikki primitiivit.

**Vielä kesken:**
- [x] **Phase 5.1+5.2: Thread/mutex/cond runtime + NURL-pinta** (shipattu 2026-05-06). Closure-field-extract `#`-cast (`# *u closure 0|1`) gen_cast:iin (~35 LOC), `nurl_thread_*` + `nurl_mutex_*` + `nurl_cond_*` `stdlib/runtime.c §19`:ään (~200 LOC POSIX `pthread` + Win32 `_beginthreadex`/`CRITICAL_SECTION`/`CONDITION_VARIABLE`), `stdlib/std/thread.nu` opaque handlein + `mutex_with` helperin kanssa. Build-skripteihin `-lpthread` Linuxille. Testi `compiler/tests/thread_basic.nu` kattaa single-thread join, 8-thread × 100-iter mutex-suojattu counter (= 800), cond_wait/cond_signal handshake. Live-tests gateattu `NURL_NET_TESTS=1`:llä run_tests:n deterministisyyden vuoksi.
- [x] **Phase 5.3: `Channel` + `server_run_pool` shipattu 2026-05-06** (`stdlib/std/channel.nu` ~150 LOC + `stdlib/ext/http_server.nu#server_run_pool` ~80 LOC). **Channel:** unbounded i64-FIFO mutex+cond+Vec[i]-pohjalla. API: `chan_new`, `chan_send Channel i v → b` (F jos closed), `chan_recv Channel → ? i` (None jos closed-ja-tyhjä, blokkaa muuten), `chan_try_recv` (non-blocking), `chan_close` (broadcastaa kaikille recvereille), `chan_len`, `chan_is_closed`, `chan_free`. ChannelImpl heap-allokoituna multi-field-structina (Mutex, Cond, Vec[i], i closed). i64-slot mahdollistaa pointterien (cast `# i raw`) sekä primitive-arvojen siirron — yleinen `Channel[T]` jää nested-generic-instantioinnin propagoinnin taakse. Testi `compiler/tests/channel_basic.nu`: single producer/consumer (sum 1..100 = 5050, count 100), closed-channel send→F, try_recv-empty→None, 2 producers × 50 + 1 consumer (sum 5050, count 100). Live-puoli gateattu `NURL_NET_TESTS=1`. **server_run_pool:** N työntekijä-threadia, jokainen ajaa `server_run_once`-silmukkaa jaetulla listenerillä (kernel serialisoi accept). `n_workers <= 1` short-circuit `server_run`:iin. **Sammutusprotokolla:** caller spawn:aa shutdown-threadin joka kutsuu `tcp_shutdown_listener` (uusi: sulkee FD:n mutta ei vapauta NurlTcp-structia → estää use-after-free workerien post-accept dereferenssissä), pool joinaa kaikki workerit, sitten caller kutsuu `server_stop` joka tekee oikean `tcp_close_listener` (vapauttaa structin kun ei enää lukijoita). Testi `compiler/tests/http_server_pool.nu` (gateattu sekä `NURL_NET_TESTS` että http_-prefix). **Tunnettu Windows at-exit-race** (~10–40% SIGSEGV process-exitissä shutdownin onnistuneen "pool: clean shutdown"-printin jälkeen) — todennäköisesti WinHTTP/CRT-atexit-vuorovaikutus, dokumentoitu Phase 8:n hardening-jatkotyöksi.
- [ ] **Phase 7+8: Conveniences + production hardening** — `serve_static`, cookie-helpers, graceful shutdown barriereineen, per-request timeoutit, slowloris-puolustus, panic recovery middleware, access-log/metrics.
- [ ] **Phase 7: Conveniences** — `serve_static`, `mime_for_ext`, cookie-helperit, form-parsing.
- [ ] **Phase 8: Production hardening** — graceful shutdown, per-request timeouts, slowloris-puolustus, panic recovery middleware, access-log/metrics.
- [ ] **Phase 9: Optional/myöhempi** — TLS, HTTP/2, WebSocket-upgrade, multipart/form-data, reverse-proxy.

### 26. `db` — tietokanta-abstraktio
- [ ] SQLite ensin (RT — `sqlite3` FFI)
- [ ] `db_open path` → `! Db IoErr`, `db_query sql params` → `! Rows DbErr` (NURL+RT)
- [ ] PostgreSQL myöhemmin (RT — libpq FFI)

### 27. `async` — asynkroninen IO
- [ ] **Iso suunnittelukysymys.** Coroutinet vs. threadit+channelit vs. async/await.
- [ ] Vaatii erillisen design-vaiheen ennen toteutusta
- **Älä toteuta ennen kuin tarve on todistettu.**

### 28. `concurrency` — säikeistys (`stdlib/std/thread.nu`, MVP 2026-05-06)
- [x] **`thread_spawn ( @ v ) f → ! Thread ThreadErr`** (`stdlib/std/thread.nu`). Käyttää closure-field-extract `#`-castia (`# *u f 0` → fn ptr, `# *u f 1` → env ptr) jolla kääntäjä hajottaa NURL-closure-arvon raaka-(fn,env)-pariksi C-runtime-trampoliinia varten. Closure on BORROWED — caller pitää sen ja sen captured envin elossa kunnes `thread_join` palaa. POSIX `pthread_create` / Win32 `_beginthreadex`. WASI: ThreadOther-stub.
- [x] **Mutex** (`mutex_new`/`_lock`/`_unlock`/`_free`/`_with`). POSIX `pthread_mutex_t`, Win32 `CRITICAL_SECTION`. `mutex_with Mutex (@ v) body → v` lukko-suorita-vapauta-helper.
- [x] **Cond** (`cond_new`/`_wait Cond Mutex`/`_signal`/`_broadcast`/`_free`). POSIX `pthread_cond_t`, Win32 `CONDITION_VARIABLE` + `SleepConditionVariableCS`. Caller pitää mutexin lukittuna ennen `cond_wait`-kutsua (POSIX-semantiikka: atomic release-and-reacquire).
- [x] **Compiler:** closure-field-extract `#`-cast (`compiler/nurlc.nu` `gen_cast`, ~35 LOC). Trigger: src on closure-shape `{ R (i8*…)*, i8* }`, dst on pointer, seuraava lex-tokeni INT 0/1. Emit: `extractvalue` + valinnainen `bitcast`. Käyttötapaus: `thread_spawn`; uudelleenkäytettävissä signal-handlereille / GTK-callbackeille / `atexit`-rekisteröinneille.
- [x] **Build:** `-lpthread` lisätty `build.sh`/`nurl.sh`/`run_tests.sh`-linkkauksiin Linuxille (`-lm`:n vieressä). Win32 ei tarvitse erillistä lippua (Win32 thread API integroitu kernelissä).
- [x] **Testi:** `compiler/tests/thread_basic.nu` — single-thread spawn+join, 8 säiettä × 100 iteraatiota mutex-suojattu counter (= 800), cond_wait/cond_signal producer/consumer-handshake. Live-tests gateattu `NURL_NET_TESTS=1`:llä koska säikeiden non-determinismi voisi muuten flakata baseline-vertailua. ThreadErr-name-taulukko unconditional.
- [x] **`Channel`** (i64-FIFO; `stdlib/std/channel.nu`, shipattu 2026-05-06): mutex+cond+Vec[i]-pohjainen unbounded jono. Yleinen `Channel[T]` jää nested-generic-instantioinnin propagoinnin taakse — i64-slot toimii sekä primitive-arvoille että pointtereille (`# i raw` ↔ `#s i`-roundtrip). Avain `server_run_pool`-shipille HTTP_SERVER_PLAN.md Phase 5.3:ssa.
- **Suunnittelupäätös:** Mutex EI ole `Mutex[T]` (typed inner — vaatisi monomorfisoinnin closure-handlejen yli), vaan tyhjä lukko. Caller suojaa shared statensa erikseen. Tämä on linjassa POSIX/pthread-konvention kanssa ja välttää generics-instantioinnin closure-shaped-T:lle (joka törmäisi multi-field-Vec-miscompile-aukkoon kunnes se korjataan).
- **Suosi message passingia jaetun tilan sijaan.** Helpompi LLM:lle. Channel[T] tulee Phase 5.3:ssa.

### 29. `serde` — yleinen serialisointi
- [ ] Trait `Serialize[T]`, `Deserialize[T]` (NURL)
- [ ] JSON, MessagePack, mahdollisesti TOML/YAML (NURL; TOML/YAML saattaa vaatia RT:tä)
- [ ] Auto-derive jos generics kestää

### 30. `uuid` — yksilölliset tunnisteet
- [x] `uuid_v4` → `String` tai `Uuid` (NURL+RT; tarvitsee `rand_bytes`)
- [x] `uuid_v7` (aikaperustainen) (NURL+RT; tarvitsee `now_ms` + random)
- [x] `uuid_parse`, `uuid_format` (NURL)

### 31. `csv` — taulukkomuotoiset tiedostot
- [x] `csv_parse s` → `! [[String ParseErr` (NURL)
- [x] `csv_write rows` → `String` (NURL)
- [x] RFC 4180 -yhteensopiva lainaus-tuki (Quoting) kaikissa rajapinnoissa (Reader/Writer/Table)
- [x] `CSVTable` arena-pohjainen: yksi `content`-puskuri + `flat_cells` (off,len)-parit, zero-copy `csv_table_view` ja owned-copy `csv_table_get`. `csv_table_a_*`-rajapinta poistettu konsolidoinnissa 2026-05-16 — kaikki kutsut `csv_table_*`:n läpi.
- [x] Header-tuki: `csv_table_col_index name → ?i`, `csv_table_get_by_name`, `csv_table_view_by_name`.

### 33. `mcp` — Model Context Protocol stdio server primitives (`stdlib/ext/mcp.nu`, MVP 2026-05-01)
LLM-host-pinon parityvuoro: NURL voi nyt tarjota itse työkaluja Claude Desktopille / claude.ai:lle MCP-protokollalla. Stdio-transport vaatii pelkät `read_line` + `nurl_print` + JSON — ei HTTP-server-riippuvuutta — joten pieni ohut framing-kerros riittää. HTTP/SSE-transport jää Tier 4 §25:n (HTTP-server) jälkeen.
- [x] **JSON-RPC framing:** `mcp_read_request → ? Json` (NDJSON-luenta, ohittaa tyhjät rivit, logaa parse-virheet stderrille ja jatkaa, palauttaa None vain EOF:lla), `mcp_send_message Json msg → v` (stringify + write + newline + flush, konsumoi msg).
- [x] **JSON-RPC envelopes:** `mcp_response_result id result → Json`, `mcp_response_error id code message → Json`, `mcp_notification method params → Json`. `id` BORROWED (json_clone-laillistettu sisäisesti), `result`/`params` CONSUMED.
- [x] **MCP shapes:** `mcp_text_content text → Json` ({type:text,text}), `mcp_tool_result_text/error text → Json` ({content:[...], isError:b}), `mcp_tool_descriptor name desc schema → Json` ({name,description,inputSchema}), `mcp_tools_list_result ( Vec Json ) tools → Json` ({tools:[...]}, KONSUMOI Vec:n), `mcp_initialize_result name version → Json` (protocolVersion 2024-11-05, capabilities.tools={}).
- [x] **Error code -vakiot:** `mcp_err_parse_error` (-32700), `mcp_err_invalid_request` (-32600), `mcp_err_method_not_found` (-32601), `mcp_err_invalid_params` (-32602), `mcp_err_internal_error` (-32603) — module-level `: i FOO -N`-konstantit (negatiivinen literaalituki Grammar v1.2).
- [x] **`mcp_log s text → v`** stderrille — stdoutista EI saa lähettää muuta kuin JSON-RPC:tä; logitus tämän kautta on pakko-konvention rikkoutumisen estämiseksi.
- [x] **Esimerkki:** `examples/mcp_echo_server.nu` (160 riviä) — täysi stdio-MCP-server yhdellä `echo`-toolilla. Käsittelee `initialize`, `notifications/initialized` (no-op + stderr-log), `ping` (empty result), `tools/list`, `tools/call` + `unknown method` -error. Toimii kun käännetään ja syötetään NDJSON-sekvenssi: `printf 'init...\nnotif...\nlist...\ncall...\n' | ./examples/mcp_echo_server` → 4 oikeanmuotoista vastausta. Kelpaa Claude Desktop / claude.ai mcpServers -konfiguraatioon binäärinä.
- [x] **Offline-testi:** `compiler/tests/mcp_basic.nu` (60 riviä) — kaikki envelope-shapet, error-koodikonstantit, tools_list_result Vec[Json]-konsumointi.
- **Suunnittelupäätös:** primitives-only, EI korkean tason `McpServer { ( Vec Tool ) tools }`-rekisteriä — `Tool` joutuisi sisältämään closure-handlerin, ja tekstipohjainen `scan_generic_structs` + closure-capture-pipeline ei vielä propagoi closure-tyyppejä `Vec[Tool]` -instantiointiin uniformisti. Käyttäjä kirjoittaa dispatch-silmukan itse ja saa vastineeksi täyden kontrollin (mm. tool-spesifinen virheenkäsittely, async-kuviot myöhemmin). Esimerkki näyttää canonical-shapen — yksi `dispatch_tool` -funktio joka switchaa nimellä.

#### 33b. `mcp_http` — Streamable-HTTP-transport MCP-serverille (`stdlib/ext/mcp_http.nu`, MVP 2026-05-05)
Viimeinen LLM-agenttihost-aukko sulkeutuu: NURL-kirjoitettu MCP-server kuuntelee nyt myös HTTP-portissa stdio-pipen sijaan. Browser-pohjaiset asiakkaat (claude.ai), HTTP-only-integraatiot ja LAN-jaetut tools-pinot toimivat suoraan ilman process-spawn-vaihetta. Erillisenä tiedostona (ei `mcp.nu`:n laajennus) jotta stdio-only-serverit eivät joudu vetämään koko HTTP-stäkkiä mukaansa.
- [x] `mcp_http_handler ( @ ? Json Json ) dispatch → ( @ HttpResponse HttpRequest )` — kääre `server_new`-yhteensopivaksi handleriksi. POST = parse → dispatch → 200 application/json (tai 202 jos dispatch palauttaa None = notifikaatio). GET = 405 (SSE-stream ei MVP:ssä). DELETE = 204 (stateless). OPTIONS = 204 + CORS-preflight-headerit.
- [x] `mcp_server_run_http s host i port ( @ ? Json Json ) dispatch → ! v NetErr` — yhden rivin convenience: `tcp_listen` + `server_new` + `server_run` blocking-loopilla. Caller voi mountata MCP:n osaksi multi-route-serveriä rakentamalla handlerin manuaalisesti `mcp_http_handler dispatch`:lla ja rekisteröimällä sen `router_post`:lla.
- [x] **Dispatch-shape** symmetrinen `examples/mcp_echo_server.nu`:n stdio-`handle`-funktion kanssa — ainoa ero on että HTTP-versio palauttaa `? Json` (Some=response, None=notification → 202) sen sijaan että kirjoittaisi `mcp_send_message`:lla. Tämä mahdollistaa stdio↔HTTP-migraation ~5 rivin muutoksella business-logiikasta.
- [x] **CORS:** Permissiivinen `Access-Control-Allow-Origin: *` + `Access-Control-Allow-Headers: Content-Type, Authorization, Mcp-Session-Id` lisätään jokaiseen vastaukseen — selainpohjaiset MCP-asiakkaat (claude.ai) toimivat ilman erillistä middleware-kerrosta.
- [x] **JSON-RPC virhe-envelope HTTP 200:ssa:** `parse_error` (-32700) malformed JSON-bodylle, `invalid_request` (-32600) tyhjälle bodylle. MCP/JSON-RPC-konvention mukaisesti HTTP-tasoiset non-200-koodit varataan kuljetustason ongelmille (404/405/500 itse runtime-puolelta), protokollavirheet kulkevat 200:ssa JSON-bodyssa.
- [x] **Esimerkki:** `examples/mcp_echo_server_http.nu` (~150 riviä) — sama `echo`-tool kuin stdio-vastineessa, sidottu `127.0.0.1:18770`:lle. Testaus: `curl -X POST http://127.0.0.1:18770/mcp -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'`. Browser-pohjainen claude.ai voi konfiguroida tämän HTTP-MCP-serverin URL:lla ilman process-spawn-vaihetta.
- [x] **Offline-testi:** `compiler/tests/mcp_http.nu` (12 keissiä, ~250 riviä) — POST initialize/notification/ping/tools_list/tools_call/unknown_method/malformed_json/empty_body, GET (405), DELETE (204), OPTIONS (204+CORS), PUT (405). Kaikki status- ja body-bytet kiintopiste-shotattu. Bootstrap-kiintopiste säilyy.
- **MVP-rajoitteet** (kaikki MCP-spec:n mukaisia, voidaan lisätä myöhemmin ilman pinta-rikkoutumista):
  - GET-puolen SSE-stream serverin lähettämille notifikaatioille (vaatii notifikaatio-jonon + Last-Event-ID:n + chunked-streaming jo shipattuna `http_response.nu`:ssa)
  - `Mcp-Session-Id`-header stateful-sessioille (per-session dispatcher + state-map)
  - JSON-RPC batch-pyynnöt (top-level `[req1, req2]`-arrayt)
  - `Accept: text/event-stream`-content-negotiation upgrade POST:lle (clientit hyväksyvät application/json:n nykyäänkin)
  - Authorization-middleware (Bearer-tokenit) — `http_router.nu`:n closure-wrapping-pattern hoitaa tämän kahdella rivillä
- **Strateginen virstanpylväs saavutettu:** §33:n "HTTP/SSE-transport ja Streamable-HTTP" -todo sulkeutuu (paitsi GET-SSE jonka voi lisätä jälkikäteen ilman pinta-muutosta). LLM-agenttihost-tarina on nyt täydellinen sekä **käyttäjäpuolelta** (NURL ajaa Clauden tools-callien kanssa) että **palvelinpuolelta** (NURL tarjoaa tools-pinon Claudelle stdio:n JA HTTP:n kautta).

- **Vielä mcp.nu:n MVP-rajoitteita** (jatkokehitys):
- [ ] Korkean tason `McpServer` + closure-pohjainen tool-rekisteri (vaatii closure-in-struct-tutkimuksen tai aliarvoisten handler-IDeiden Vec-pohjan)
- [ ] `prompts/list`/`prompts/get` ja `resources/list`/`resources/read` -kapasiteetit (lisätään konvention mukaisesti samalla shapella kun tarve)
- [ ] MCP-asiakas (NURL → toinen MCP-server, esim. agentti joka käyttää tooleja); vaatii subprocess-stdio-pipen `process_run`-rajapinnan päälle laajennettuna duplex-streaming-tilaan
- [ ] Streaming-vastaukset (`tools/call` joka tuottaa progress-notifikaatioita ennen lopullista resultia) — vaatii async/non-blocking-IO-päätöksen Tier 4 §27:ssa
- [ ] Server-pushed notifikaatiot HTTP-puolella (GET /mcp SSE-stream) — chunked-streaming-primitiivit jo paikallaan, tarvitaan vain notifikaatio-jono

### 32. `anthropic` — Claude Messages API client (`stdlib/ext/anthropic.nu`, MVP 2026-05-01)
LLM-host-kielen lukko-osa: kun NURL:n omat ohjelmat voivat ajaa Claudea HTTP+JSON-pohjalta, "designed for LLMs" on konkreettinen eikä pelkkä periaate. Pohjana on koko Tier 2 (`http`, `http_json`, `json`, `env`) — tämä moduuli on ohut komposiittori joka rakentaa Messages-pyyntörungon, asettaa `x-api-key` + `anthropic-version`-headerit, lähettää POSTin `https://api.anthropic.com/v1/messages`:iin ja palauttaa parsitun JSON-vastauksen.
- [x] `claude_messages s api_key s model s system_prompt s user_text i max_tokens → ! Json ClaudeErr` — ainoa pyyntö-rajapinta (single-turn). `system_prompt` `` ohittaa `system`-kentän kokonaan.
- [x] `claude_text Json r → s` — kävelee `content`-arrayn ja palauttaa ensimmäisen `{type:"text"}`-blokin `text`-kentän. Lainattu `s`-näkymä; tyhjä string kun ainoastaan tool_use-blokkeja tai shape-mismatch.
- [x] `claude_stop_reason Json r → s` / `claude_model Json r → s` — lainatut näkymät.
- [x] `claude_input_tokens Json r → i` / `claude_output_tokens Json r → i` — `usage`-blokin tokenmäärät (0 jos puuttuu).
- [x] `claude_response_free Json r → v` — alias `json_free`:lle, pidetään moduulin nimiavaruudessa LLM-koodin löytyvyyden vuoksi.
- [x] `ClaudeErr` enum: `ClaudeAuth | ClaudeHttp{Connect,Timeout,Tls,Dns,InvalidUrl,Other} | ClaudeJson | ClaudeApi | ClaudeShape`. HTTP-puolen variantit ovat 1:1 mappaus `HttpErr`:stä, jotta caller saa diagnostisen polun ilman ulompaa httperror-knowledgea. `ClaudeApi` = HTTP non-200 response (rate-limit, auth-fail, jne.); `ClaudeJson` = body ei ollut validia JSONia; `ClaudeAuth` = api_key oli tyhjä (early-return ennen verkkokutsua).
- [x] `claude_err_name ClaudeErr e → s` — diagnostiikkahelper variant-nimellä.
- [x] **Esimerkki:** `examples/claude_chat.nu` — minimal CLI joka lukee `ANTHROPIC_API_KEY`:n ympäristöstä + argv-promptin, lähettää viestin `claude-opus-4-7`:lle ja tulostaa vastauksen + token-käytön. Linja 60 käyttäjäkoodia; toimii copy-paste-pohjaisena LLM-agenttihostingin demoa.
- [x] **Testi gateattu offlineksi:** `compiler/tests/anthropic_basic.nu` — empty api_key → ClaudeAuth + kaikki 10 variantin nimet. Ei verkkokutsua. Live-API-testit jäävät käyttäjälle (vaatii API-avainta + maksaa rahaa per call).
- **Suunnittelupäätös:** ei `! ClaudeResponse ClaudeErr` vaan `! Json ClaudeErr` — käyttäjä saa raaka-Json:in jonka voi `json_get path`-syntaksilla probata mitä tahansa kenttää (`response.id`, `response.usage.cache_read_input_tokens` jne.). Stdlib-puoli tarjoaa vain useimpien tapauksien convenience-accessorit. Tämä pitää API-pinta-alan pieneksi ja koostuu hyvin tool-use- ja extended-thinking-flageiltä myöhemmin (kun ne lisätään, accessorit kasvavat mutta runko ei muutu).
- **Endpoint hardcoded** `https://api.anthropic.com/v1/messages`:iin, `anthropic-version: 2023-06-01`. Eri endpointin (proxy / Bedrock / Vertex) caller voi tehdä `http_post_with_headers`-kutsulla suoraan (kopioi `__claude_build_body` + `__claude_headers`-helperit).
- **Multi-turn + tool-use shipattu 2026-05-01** (`claude_messages_full`):
- [x] `claude_messages_full s api_key s model s system_prompt ( Vec Json ) messages ( Vec Json ) tools s tool_choice i max_tokens → ! Json ClaudeErr` — täysi pinta. Vec[Json]-syötteet **lainattu** (deep-clone per kutsu) → caller pitää saman messages/tools-Vec:in koko agenttisilmukan ajan. Yksinkertainen `claude_messages` säilyy ohuena wrapperinä → olemassa oleva `examples/claude_chat.nu` toimii muuttumatta.
- [x] **Message-rakentajat:** `claude_msg_user_text s text → Json`, `claude_msg_assistant_text s text → Json`, `claude_msg_assistant_response Json r → Json` (kloonaa r["content"]:n ja kääriin `{role:"assistant", content:[…]}`), `claude_msg_user_blocks ( Vec Json ) blocks → Json` (CONSUMES blocks, käytetään tool_result-turn:n rakentamiseen), `claude_tool_result_block s tool_use_id s text b is_error → Json`.
- [x] **Tool-deskriptori:** `claude_tool_def s name s description Json input_schema → Json` (CONSUMES input_schema). Anthropic käyttää snake_case `input_schema` (vrt. MCP camelCase `inputSchema`).
- [x] **`tool_choice` raaka-`s` syntax:** `""` (omit, default = auto kun tools ei tyhjä) | `"auto"` | `"any"` (pakota tool-use) | `"none"` (kielitä tools) | `"tool:NAME"` (pakota tietty tool). Parsittu `__claude_parse_tool_choice`:ssa, tool:NAME-suffix `string_substr`-pohjalla puhtaalla ownershipillä.
- [x] **Vastauksen extractorit:** `claude_has_tool_use Json r → b` (stop_reason == "tool_use"), `claude_tool_calls Json r → ( Vec Json )` (omistettu Vec, kloonatut tool_use-blokit jotta caller voi vapauttaa response Json:n itsenäisesti — vapauta closurella `\ Json e → v { ( json_free e ) }` + `vec_free_with`), `claude_tool_use_id/name/input` (lainatut näkymät; input on `? Json`).
- [x] **Esimerkki:** `examples/claude_agent.nu` (~280 riviä) — täysi agenttisilmukka jossa Claude saa `run_shell` (process_run_shell-pohjalla) + `read_file` (fs.read_file-pohjalla)-toolit. Loop max 8 kierrosta, output-truncatio 8000 tavua per tool jotta wild `find /` ei räjäytä konteksti-ikkunaa, error-detection (`error:`-prefix → `is_error: true` Claudelle).
- [x] **Offline-testi:** `compiler/tests/anthropic_tools.nu` — kaikki message-shapet, 5 tool_choice-muotoa, tool_calls-poiminta synteettisestä responsesta (1 text + 2 tool_use-blokkia), ClaudeAuth-cleanup non-empty msgs+tools:lla. ASan-puhdas.
- **Suunnittelupäätös:** Vec[Json]-syötteet lainataan (eikä konsumoida kuten `mcp_tools_list_result`:ssa) koska agenttisilmukka-käyttötapaus tarvitsee saman Vec:in moneen kutsuun → yksi clone per kierros on halpa verrattuna verkkoreitti-kustannukseen. Asymmetria MCP:hen on tahallinen — eri use case, eri konvention.
- **HTTP-timeout 600 s default** (2026-05-01): `claude_messages_full` käyttää `http_request_to`:ta 600 000 ms total + 15 000 ms connect — sama default kuin virallisen Anthropic SDK:n. Ilman tätä monikierros-agenttisilmukat aikakatkesivat 30 s:n MVP HTTP-budgetin takia jokaisen toisen kierroksen kohdalla. **`ANTHROPIC_TIMEOUT_MS` env-override** sallii käyttäjän nostaa/laskea ilman uudelleenkääntämistä (out-of-range/parse-fail → 600 s).
- **Prompt caching + extended thinking shipattu 2026-05-01** (`claude_messages_full_ex`):
- [x] `claude_messages_full_ex … b cache_system b cache_tools i thinking_budget → ! Json ClaudeErr` — täysi pinta. Vanha `claude_messages_full` säilyy ohuena `F F 0`-wrapperinä → backward-compat, ei migraatiota olemassa olevaan koodiin.
- [x] **Caching:** `cache_system: T` switchaa system-promptin array-formiin `[{type:"text",text:...,cache_control:{type:"ephemeral"}}]`; `cache_tools: T` lisää `cache_control:{type:"ephemeral"}` viimeiseen tool-defiin (peittää koko tools-arrayn pisimpänä cache-prefiksinä). Per-message breakpoints helpereillä `claude_msg_user_text_cached` / `claude_msg_assistant_text_cached`. Anthropic-rajoite: max 4 cache_control per pyyntö; typical setup 2 (system+tools).
- [x] **Extended thinking:** `thinking_budget > 0` emittaa `{"thinking":{"type":"enabled","budget_tokens":N}}` → Claude tuottaa thinking-blokkeja content-arrayhin ennen vastausta. 0 disabloi.
- [x] **Cache-token-accessorit:** `claude_cache_creation_tokens Json r → i` (kirjoitettu välimuistiin, full-price), `claude_cache_read_tokens Json r → i` (luettu välimuistista, ~10% input-rate). Caller voi seurata cache-osumista live-tuotannossa.
- [x] **Offline-testi:** `compiler/tests/anthropic_tools.nu`-laajennos kattaa cached msg builderit, kaikki neljä body-shape-yhdistelmää (cache_system/cache_tools/molemmat+thinking/empty-system+cache_system), cache-token-poiminta + missing-usage→0.
- **Vision + dokumentit shipattu 2026-05-01:**
- [x] **Multimodal content blocks** (`stdlib/ext/anthropic.nu`). 5 ohutta `Json`-rakentajaa peilaamassa `claude_tool_result_block`-mallia: `claude_text_block s text → Json`, `claude_image_url_block s url → Json` (server-side fetch), `claude_image_b64_block s media_type s data_b64 → Json` (`image/png|jpeg|gif|webp`), `claude_document_url_block s url → Json` ja `claude_document_b64_block s data_b64 → Json` (PDF, media_type hardcoded `application/pdf`:hen). Käyttötapa: pushaa Vec[Json]:iin yhdessä text-blokkien kanssa → kääri `claude_msg_user_blocks`:lla → syötä `claude_messages_full`:lle. Memory model: kaikki `s`-syötteet BORROWED — literaalit + `string_data` toimivat suoraan. Offline-testi `compiler/tests/anthropic_tools.nu` §4e: jokainen 5 blokin shape + täysi `text + image_url`-user-turn. Inline-base64-pohjalla paikallinen kuva: `read_file_bytes path` → `b64_encode ( bytes_to_str v )` (tai uudemman `b64_encode_bytes`-helperin kun se shipataan).
- **Streaming SSE shipattu 2026-05-01:**
- [x] **HTTP streaming** (`stdlib/runtime.c §14b` libcurl multi-handlen päällä, `stdlib/ext/http.nu` NURL-pinta, `compiler/tests/sse_parser.nu`). Pull-pohjainen — NURL draivaa transferia chunki kerrallaan ilman threadeja. **Runtime:** `nurl_http_stream_open_to/next/status/err_kind/close` libcurl-haarassa; WinHTTP + WASI saavat HttpOther-stubit. **NURL:** `HttpStream { i raw }` opaque handle, `http_stream_open[_to]`, `http_stream_next → ? String` (owned chunk; None = EOF), `http_stream_status`, `http_stream_err → ? HttpErr`, `http_stream_close`. **SSE-parseri** stateless-pohjalla (NURL ei tue typed struct-kentän mutaatiota): `sse_frame_end s acc i len → i` (-1 = partial), `sse_parse_frame s frame i len → SseEvent { name data id }`, `sse_event_free`. Caller pitää `~ String acc`-akkumulaattoria, kutsuu pop-loopin chunkkien välissä.
- [x] **Anthropic streaming** (`claude_messages_stream_ex` täysi pinta + `claude_messages_stream` single-turn-shim): asettaa body:yn `stream: true`, lisää `accept: text/event-stream`-headerin, palauttaa `! HttpStream ClaudeErr`. Vec[Json] borrow-semantiikka ennallaan. **Convenience-extractori** `claude_stream_event_text_delta SseEvent → ? String` poimii yleisimmät `content_block_delta`-eventit (`delta.type == "text_delta"`). Caller-loop näyttää tältä:
  ```
  : ~ String acc ( string_with_cap 1024 )
  : ~ b done F
  ~ ! done {
    : ? String chopt ( http_stream_next st )
    ?? chopt {
      T ch → {
        ( string_push_str acc ( string_data ch ) )
        ( string_free ch )
        : ~ b inner F
        ~ ! inner {
          : i fend ( sse_frame_end ( string_data acc ) ( string_len acc ) )
          ? < fend 0 { = inner T } {
            : SseEvent ev ( sse_parse_frame ( string_data acc ) fend )
            // ...käsittele ev (esim. text_delta-tarkistus)...
            ( sse_event_free ev )
            : i tot ( string_len acc )
            : i drop + fend 2
            : String r ( string_substr acc drop - tot drop )
            ( string_free acc )
            = acc r
          }
        }
      }
      F → { = done T }
    }
  }
  ( http_stream_close st )
  ( string_free acc )
  ```
- **Vielä jatkokehityksessä:**
- [ ] Tool-use stream-events extractor (`claude_stream_event_input_json_delta`) — yksi mirror-funktio kun joku tarvitsee live-tool-call streamingia
- [ ] Streaming-versio HTTP serverille (Tier 4 §25 ensin)

---

## Tier 5 — Erikoistarpeet (tarpeen mukaan)

Nämä syntyvät käyttäjäkysynnästä, eivät ennakoiden.

- [ ] `compress` — gzip, zstd (RT — zlib/zstd FFI)
- [ ] `image` — PNG/JPEG (RT — stb_image tai libvips FFI)
- [ ] `xml` — vain jos tarve syntyy (NURL)
- [ ] `math_advanced` — kompleksiluvut, matriisit (NURL, skalaarit libm:stä)
- [ ] `embedded` — `no_std`-profiili mikroille (Tier 4-alueella)
- [ ] `wasm_bindings` — WebAssembly-target
- [ ] `ml_tensor` — jos joku haluaa tehdä ML:ää (RT — ONNX/GGML FFI)

---

## Yhteenveto — mikä kuuluu NURL:iin vs. runtime.c:hen

### Kirjoitetaan **NURL:lla** (ei lisätä runtime.c:hen)
Option/Result-combinaattorit, `Vec[T]`, geneerinen `HashMap[K V]`, `Set[T]`, `iter`-ketju,
`sort`/`binary_search`/`min`/`max`/`clamp`, polku-käsittely (`path_*`), `int_abs/min/max/pow`,
string-operaatiot owned-`String`:n päällä (split, trim, to_lower, replace, repeat…),
JSON-parseri ja -serialisoija, regex (NFA NURL:ssa), CSV, `fmt`, `log`,
base64/hex-enkoodaus, `bytes`-lukeminen `nurl_peek`:in päälle, `Time`-kenttälasku,
vakiot (`INT_MAX`, `PI` literaalina), HTTP-server, serde-trait, uuid-logiikka.

### Lisätään **runtime.c**:hen (alkuvaiheessa)
**Pakolliset Tier 0 → Tier 1:n valmistumiseksi:**
1. ~~`nurl_memset`~~ (valmis), ~~`nurl_str_to_float`~~ (valmis), ~~`nurl_str_cmp`~~ (valmis 2026-04-27, `stdlib/std/cmp.nu`:n pohja). Triviaalit, viimeistelevät numeeriset ja muistin.
2. ~~`nurl_read_line`~~ (valmis), `nurl_read_all_stdin`, ~~`nurl_flush_stdout`/`nurl_flush_stderr`~~ (valmis) — stdin/stdout viimeistely.
3. ~~`nurl_dir_create`~~ (valmis 2026-04-26), ~~`nurl_dir_remove`~~ (valmis 2026-04-26), ~~`nurl_dir_list_open/next/close`~~ (valmis 2026-04-28 — POSIX `opendir/readdir/closedir`, Win32 `FindFirstFile/FindNextFile/FindClose`).
4. ~~`nurl_read_file_safe`~~ + ~~`nurl_write_file_safe`~~ + ~~`nurl_errno_kind`~~ (valmis 2026-04-26 — `stdlib/std/fs.nu`:n pohjana). `nurl_file_read_chunk`, `nurl_file_readline` — fread/fgets — yhä auki.

**Pakolliset Tier 2:n valmistumiseksi:**
5. ~~`nurl_now_ms`, `nurl_now_seconds`, `nurl_monotonic_ns`, `nurl_sleep_ms`~~ (valmis 2026-04-27 — runtime.c §12, käyttää `clock_gettime` + `nanosleep`/`Sleep`-portattava). Linkkaus tarvitsee `-lm` joka lisättiin `build.sh`/`nurl.sh`/`run_tests.sh`:hen.
6. ~~`nurl_env_get/set/unset`, `nurl_cwd`, `nurl_chdir`, `nurl_read_all_stdin`~~ (valmis 2026-04-28 — runtime §13 CLI tooling, POSIX `getenv/setenv/unsetenv/getcwd/chdir` ja Win32 `_putenv_s/_getcwd/_chdir`).
7. ~~libm-sillat: `nurl_sqrt`, `nurl_floor`, `nurl_ceil`, `nurl_round`, `nurl_sin`, `nurl_cos`, `nurl_tan`, `nurl_atan2`, `nurl_log`, `nurl_exp`, `nurl_pow`, `nurl_fabs`, `nurl_is_nan`, `nurl_is_inf`~~ (valmis 2026-04-27 — runtime.c §11, linkkaa `-lm`). Lisäksi `nurl_iabs`, `nurl_ipow` puhtaina i64-helpereinä.
8. ~~`nurl_str_to_float_safe` + `nurl_str_float_value`~~ (valmis 2026-04-27 — strict strtod-pohja sideband-arvolla, `float_parse`:n perusta).
9. ~~`nurl_rand_u64`, `nurl_rand_bytes_hex`~~ (valmis 2026-04-30 — runtime §17, `getrandom`/`arc4random_buf`/`BCryptGenRandom` + `/dev/urandom`-fallback). Lisäksi self-contained `nurl_sha256_hex` ja `nurl_hmac_sha256_hex` (FIPS 180-4 + RFC 2104) — ei libsodium-linkkausta.

**Tier 3+ mukana kun tarve:**
9. `nurl_http_get/post` — libcurl (ei ilman linkkausta).
10. `nurl_tcp_*`, `nurl_udp_*`, `nurl_dns_resolve` — BSD socketit.
11. ~~`nurl_proc_run` + accessorit (`nurl_proc_exit_code/stdout/stderr/err_kind/free`)~~ (valmis 2026-04-30 — runtime §16, POSIX `fork/execvp/poll` + Win32 `CreateProcess`+reader-threadit; WASI-stubi). `nurl_proc_spawn` async-handlena jää jatkokehitykseen.
12. `nurl_sha256/512`, `nurl_hmac_sha256` — libsodium.
13. `nurl_sqlite_*` — sqlite3.
14. `nurl_thread_spawn`, `nurl_mutex_*`, `nurl_cond_*` — pthreads.
15. `nurl_realpath` — `realpath()` canonicalisointiin.

### Siivottavaa runtime.c:stä
Bootstrap-kompilaattorin tuki (`nurl_lex_*`, `nurl_sym_*`, `nurl_cg_*`, `nurl_get_last_type`/`nurl_set_last_type`, `nurl_print_buf_*`) poistetaan kun kääntäjä itsehostuu ilman niitä. Aika tehdä siivous: kun memory-management-prosessi sallii kääntäjän noudattaa omia sääntöjään (opt-out-pragman poisto).

---

## Toteutusjärjestys — käytännön suositus

**Sprint 1 (1–2 viikkoa):** Tier 0 kokonaan
Ilman tätä mikään muu ei kanna. Lisää RT:hen `memset`, `read_line`, `flush`. Rakenna
`core/string.nu`, `core/vec.nu`, `core/option.nu`, `core/result.nu`, `core/io.nu`, `core/mem.nu`.

**Sprint 2 (1–2 viikkoa):** Tier 1 ydin (`fs`, `hashmap`, `iter`, `cmp`/`sort`)
Lisää RT:hen `dir_create`, `dir_list`, `file_read_chunk`, `float_from_string`. Tässä kohtaa
NURL:lla voi kirjoittaa oikean CLI-työkalun (esim. `wc`, `grep`, oma JSON-formattaja).

**Sprint 3 (2–3 viikkoa):** Tier 2 valittu osa
Suosittelen järjestystä: `env` → `time` → `json` → `regex` → `http`.
RT:hen vähintään `env_*`, `now_*`, `sleep_ms`. JSON ja regex ovat puhdasta NURLia.
HTTP vaatii libcurl-FFI:n.

**Sprint 4+:** Tier 3+ priorisoituna käyttäjäkysynnän mukaan
Ei ennakoivaa toteutusta — ne valmistuvat sitä mukaa kun joku oikeasti tarvitsee niitä.

---

## Suunnitteluperiaatteet jokaiselle kirjastolle

1. **Yksi tapa.** Älä tarjoa `string_concat` ja `string_append` ja `string_join_one` — valitse yksi nimi.
2. **Failure on `! T E`.** Ei hiljaisia virheitä, ei nullia paitsi `?T`:n kautta.
3. **Single-owner.** Funktiot kuluttavat tai eivät kuluta argumentit, dokumentoidusti. Oletusarvoisesti kuluttavat.
4. **Pieni nimiavaruus.** Prefixit (`vec_`, `string_`, `map_`) jotta LLM löytää funktiot kontekstista.
5. **Esimerkit testeissä.** Jokainen julkinen funktio testitiedostossa joka näyttää käyttötavan.
6. **Token-tehokkuus.** `vec_push xs x` ei `vector_append_element_to_back xs x`.

---

## Kirjastojen sijoittelu (tavoite)

```
stdlib/
├── runtime.c              — C-runtime (FFI-pohja, libm/libcurl/libsodium-sillat)
├── runtime.o
├── core/                  — Tier 0, automaattisesti tuotu prelude
│   ├── mem.nu
│   ├── string.nu
│   ├── vec.nu
│   ├── pair.nu             ✓ MVP (2026-04-28)
│   ├── option.nu
│   ├── result.nu
│   └── io.nu
├── std/                   — Tier 1
│   ├── fs.nu              ✓ MVP
│   ├── hashmap.nu         ✓ MVP
│   ├── iter.nu            ✓ MVP (eager range; trait-pohjainen iter myöhemmin)
│   ├── set.nu             ✓ MVP
│   ├── cmp.nu             ✓ MVP (2026-04-27)
│   ├── sort.nu            ✓ MVP (2026-04-27)
│   ├── int.nu             ✓ MVP (2026-04-27)
│   ├── float.nu           ✓ MVP (2026-04-27)
│   ├── time.nu            ✓ MVP (2026-04-27)   — siirretty std/:hen koska
│   │                                              pelkkä RT-bridge, ei vaadi
│   │                                              ulkoisia kirjastoja
│   ├── path.nu            ✓ MVP (2026-04-28)
│   ├── fmt.nu             ✓ MVP (2026-04-30)
│   ├── log.nu             ✓ MVP (2026-04-30)
│   ├── process.nu         ✓ MVP (2026-04-30)
│   ├── encode.nu          ✓ MVP (2026-04-30) — hex + base64 (RFC 4648)
│   ├── hash.nu            ✓ MVP (2026-04-30) — SHA-256 + HMAC-SHA-256
│   ├── random.nu          ✓ MVP (2026-04-30) — getrandom-pohja
│   └── bytes.nu           ✓ MVP (2026-05-01) — Vec[u]-pohja + hex/str-roundtrip
└── ext/                   — Tier 2+
    ├── json.nu            ✓ MVP (2026-04-26)
    ├── env.nu             ✓ MVP (2026-04-28)
    ├── regex.nu           ✓ MVP (2026-04-28)
    ├── http.nu            ✓ MVP placeholder (2026-04-28)
    ├── http_json.nu       ✓ MVP (2026-04-29)
    ├── anthropic.nu       ✓ MVP (2026-05-01) — Claude Messages API
    ├── mcp.nu             ✓ MVP (2026-05-01) — MCP stdio server primitives
    └── ...
```

Käyttäjä importtaa: `$ \`stdlib/core/string\``, `$ \`stdlib/std/json\``.
Tier 0:n moduulit voisivat olla **automaattisesti tuotuja** (prelude) — mietittävä erikseen.

---

## Mitä **ei** kuulu stdlibiin

- GUI-kirjastot (käyttöjärjestelmäriippuvaisia, FFI parempi)
- ORM:t (sovelluskohtaisia)
- Web-frameworkit (mielipidekysymyksiä, ekosysteemi rakentaa)
- AI/ML-kirjastot (FFI olemassaoleviin: ONNX, GGML, llama.cpp)
- Pelimoottorit
- Erikoistuneet tieteelliset paketit (BLAS, FFT)

Stdlib pidetään **fokusoituna ja hyvin testattuna**. Ekosysteemi rakentaa loput.
