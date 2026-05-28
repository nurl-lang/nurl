# NURL — Korjattavat asiat (kriittisen arvioinnin pohjalta)

Lähde: ulkoinen tekninen review (47/100). Tärkein punainen lippu: **`play.nurl-lang.org` MCP palvelee dokumentaatiota ja artefakteja, joita ei näy julkisessa `main`-puussa**.

---

## Tier 1 — pakolliset ennen kuin voidaan väittää tuotantokelpoiseksi

- [x] ~~**Pushaa loput repoa `main`iin.**~~ — Tarkistettu 2026-05-28: kaikki reviewerin "puuttuvaksi" väittämät artefaktit ovat jo `origin/main`issa (`bench/`, `tools/{nurlfmt,nurl-lsp,nurlpkg}`, `BORROW.md`, `docs/{MEMORY,spec}.md`, `.github/workflows/ci.yml`). Reviewer katsoi väärää lähdettä — tämä oli iso punainen lippu joka ei ollut todellinen.

- [ ] **Julkaise reprodusoitavat benchmark-skriptit.**
  - [ ] `bench/run.sh` (yhden komennon ajo)
  - [ ] Lähdetiedostot per kieli (NURL/Python/Rust/Node, ja Go kun asennettu)
  - [ ] CI-job kiinteällä speksillä (esim. GitHub Actions `ubuntu-latest` 2-vCPU) joka kirjoittaa taulukon versioituun tiedostoon
  - [ ] Tavoite: kuka tahansa contributor saa `make bench`-ajolla 20 %:n tarkkuudella julkaistut luvut
  - [ ] HTTP-bench `oha 1.8.0`: dokumentoi 8-worker poolin koko ja se että C=10 piikki johtuu pool-koosta, ei yleisestä paremmuudesta hyperiin nähden

- [ ] **Hanki yksi ulkoinen contributor jonka PR koskee kääntäjää.** Bus factor 1 on dominoiva riski; kunnes toinen ihminen on mergennyt ei-triviaalin compiler-muutoksen, kaikki muu insinöörityö riippuu yhdestä henkilöstä.

## Tier 2 — kunnollisen kielen hygienia

- [~] **Aja HTTP/2 + WebSocket interop-suite oikeita työkaluja vasten** ("offline RFC-vector verification" = unit test, ei interop):
  - [~] `h2spec v2.6.0` (146 conformance casea RFC 7540 + RFC 7541 HPACK vasten)
    - **Tila 2026-05-28: 135/146 läpäisee** (lähtö 0/146; ei UAF:ää, build vihreä)
    - Korjatut juurisyyt (commitit `9f1f12b`, `52426e6`):
      - 4 parenthesoitua operaattori-ilmaisua (`( % n 6 )`, `( . rp from )`) — diagnoosi olemassa 2026-05-22 jälkeen, http2_conn.nu vain ei ollut build-pathilla
      - `nurl_str_slice_unsafe` löi load-byten pointer-aritmetiikan sijaan
      - `__h2_frame_err_to_conn` ei castannut bare enum-tagia paluuarvon enum-tyyppiin (vrt. `__net_err_of` -konventio)
      - `__h2_stream_to_request` vapautti `req.query`:n ehdoitta mutta uudelleenassignoi vain `?`-haaroitusbranchissa → use-after-free `request_free`:ssa
      - `__h2_decode_stream_headers` vapautti `cur.dec_dyn`:n ennen kuin assignoi `dd.dyn`:in; HpackDynTable-rakennetta välitetään arvona mutta sisempi entries-Vec on aliasoitu → kaksoisvapautus
      - `hpack_decode_block`-virhepolku vapautti `cur`:in (= aliasoitu input dyn) → kutsuja sai dangling-pointterin
      - HPACK encoder ei lowercase-änyt header-nimiä (RFC 9113 §8.2.2 vaatii) → curl/h2 hylkäsi `Content-Type`
      - SETTINGS/GOAWAY/RST_STREAM/PRIORITY/DATA stream-ID + length + ACK -säännöt lisätty
      - GOAWAY-vastaanotto: ei enää välitön sulkeminen vaan §6.8 mukainen in-flight-frame-käsittely
    - **Korjattu välietapeissa (commitit `52426e6` `0cfeca6` ja `<seuraava>`):**
      - Frame-validation pass (SETTINGS/GOAWAY/RST_STREAM/PRIORITY/DATA stream-ID + length + ACK)
      - HEADERS §8.3 pseudo-header validointi (uppercase, duplikaatit, missing/empty, connection-specific, TE != trailers, response-only-pseudo, pseudo-after-regular, unknown-pseudo)
      - PRIORITY / HEADERS-with-PRIORITY-flag self-dependency §5.3.1
      - PUSH_PROMISE rejection §6.6
      - Flow-control window overflow §6.9.1 (connection + stream RST_STREAM)
      - WINDOW_UPDATE idle stream §5.1
      - SETTINGS/WINDOW_UPDATE byte-mask (sign-extend gotcha)
      - HPACK §4.2 dynamic table size update placement + bound by SETTINGS_HEADER_TABLE_SIZE
      - Invalid preface → GOAWAY ennen sulkua
      - h2c-test-serverin per-connection timeout (sekventiaalinen accept-silmukka ei jämähdä)
    - **Jäljellä 11 uniikkia failurea (kovan luokan jäljelle jättämättömät):**
      - **3 timing-flakea** — passes alone, fails aggregate. Vaatii concurrent accept-silmukan (async runtime) tai ratkaisun siihen miksi h2spec päättelee ennen serverin ACKia jossain tietyissä testeissä. Tests: "Sends a SETTINGS frame without ACK flag", "Sends multiple CONTINUATION frames preceded by a HEADERS frame", "Sends a SETTINGS_INITIAL_WINDOW_SIZE settings with an exceeded maximum window size value"
      - **2 content-length** — vaatii: tallenna `content-length` headerista, kerää DATA-tavujen yhteissumma, vertaile END_STREAM:llä
      - **1 POST trailers (`generic/4/4`)** — HEADERS sallittava jo avoimella streamilla trailerina (state open/half-closed-local, MUST END_STREAM, ei pseudo-headereita); meidän koodi torjuu uudelleenkäytetyn sid:n
      - **5 SETTINGS edge case** — pääosin timing (passes alone): multi-value INITIAL_WINDOW_SIZE, change-after-HEADERS, init=1+HEADERS, negative window, WINDOW_UPDATE flow-control > 2^31-1 conn-level
  - [ ] `autobahn-testsuite` (WebSocket) — vielä aloittamatta. `crossbario/autobahn-testsuite` -Docker image valmis ajettavaksi.
  - [ ] Konteksti: CVE-2023-44487 ("HTTP/2 Rapid Reset"), CVE-2019-9511…9518 -klusteri, CVE-2026-23918 (Apache `mod_http2` double-free) — RFC-appendix-vektorit eivät kata näitä
  - **Työkalut:**
    - `/home/wau/.local/bin/h2spec` (v2.6.0) asennettu
    - `examples/h2c_server.nu` minimal h2c-prior-knowledge serveri portissa 8443
    - Sanitizer-build-skripti `/tmp/build_san.sh` (ASan+UBSan, native runtime.o ilman LTO:ta) — käytä bug-debuggaukseen
    - Ajo: `/tmp/h2c_san > /tmp/svr.log 2>&1 &; h2spec -h 127.0.0.1 -p 8443 -o 3 > /tmp/h2spec.log 2>&1`

- [ ] **Julkaise tokenizer-aware token-tehokkuusvertailu.**
  - [ ] Aja Claude (cl100k variant), GPT-4o (o200k), Llama 3 BPE-tokenizerit ekvivalenttia NURL/Python/C/Rust-koodia vasten eri kokoluokissa
  - [ ] Julkaise todelliset token-määrät — nykyinen "~15 vs ~4 tokens" laskee whitespace-eroteltuja atomeja, ei BPE-subwordeja
  - [ ] Realistinen tarina luultavasti edelleen NURL-suuntainen, mutta vähemmän dramaattinen

- [ ] **Syvennä borrow-checker (Miri-ekvivalentti memory check).**
  - [ ] `--strict-borrowck` -mode joka nappaa interprosedural- ja `*T`-escapet jotka nykyinen checker myöntää jättävänsä huomiotta
  - [ ] Korkea false-positive -kustannus ok — borrow-checker on puolustettavin turvallisuusväite, syvennä sitä

## Tier 3 — yhteisö & markkinointi

- [ ] **Kirjoita Show HN -postaus.**
  - [ ] Lead-angle: MCP-server-as-toolchain (vahvin novel pitch)
  - [ ] Zero external community on tällä hetkellä äänekkäin punainen lippu
  - [ ] Algolia API: `nbHits=0` sekä `nurl-lang` että `"Neural Unified Representation Language"` -hauilla

- [x] **Poista "non-human readable" -framing.** Marketing-haava. (Commit `1277711`)
  - [x] README otsikon "(or Non-hUman Readable Language)" poistettu
  - [x] Tagline ja "Why NURL?" rewritetty defensible-property-listaukseksi (regular grammar, local semantics, determinism, single-owner memory + borrow checker, LLVM reach)
  - [x] "Token efficiency in practice" + Python/NURL token-vertailu poistettu
  - [x] `bench/README.md` ja `docs/FORMAT.md` siivottu vastaavasti

---

## Erilliset tekniset huomiot reviewstä (taustaksi, ei suoraan TODO)

- **Prefix-cascade**: rakenteellisesti mahdoton täysin eliminoida operator-arity-grammasta ilman grammar-muutosta; diagnostic-hint olemassa mutta vain ~12 päivää julkista elinkaarta.
- **TCO**: shipattu LLVM `tail`-hint (ei `musttail`). Syvä rekursio voi silti pakottaa stack-overflowin jos LLVM-analyysi declinaa hintin. ROADMAP perustelee `musttail`-välttelyn owning-ABI:lla — fair, mutta optimisaatio voi silently degradoitua.
- **Async runtime**: shipattu 2026-05-23 (`stdlib/std/async.nu`), tunnetut racet (TLS-through-LTO, reactor park/unpark, same-handle sync+async mix) — alle viikon vanhalla runtimella ei aja todistamattomia workloadeja.
- **SQLite-bridge**: vain text + int64; ei BLOBia, ei doublea.
- **PostgreSQL-bridge**: vain text format, ei async, ei `LISTEN/NOTIFY`, ei `COPY` streaming.
- **JSON deserialize**: ei `Deserialize` traitia by design (first-arg-dispatch ei kanna receiveriä `Json`).
- **Closure captures**: käyttävät edelleen RC env-blockia.
- **`recover` scopes**: vuotavat owned allocations.
- **Signaalit**: ei bridgetty NURL-puolelle.
- **Struct-parametrit**: pass-by-value, `= . p field val` kirjoittaa lokaaliin kopioon ellei `inout`.

---

## Reviewerin score-breakdown (referenssiksi)

| Kategoria | Score |
|---|---:|
| Language design | 6/10 |
| Compiler architecture | 7/10 |
| Standard library | 6/10 |
| Tooling | 5/10 |
| Memory model / safety | 5/10 |
| Benchmarks & comparisons | 2/10 |
| Documentation | 6/10 |
| Maturity & sustainability | 2/10 |
| **Overall** | **47/100** |
