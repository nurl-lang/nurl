# NURL — Korjattavat asiat (kriittisen arvioinnin pohjalta)

Lähde: ulkoinen tekninen review (47/100). Tärkein punainen lippu: **`play.nurl-lang.org` MCP palvelee dokumentaatiota ja artefakteja, joita ei näy julkisessa `main`-puussa**.

---

## Tier 1 — pakolliset ennen kuin voidaan väittää tuotantokelpoiseksi

- [ ] **Pushaa loput repoa `main`iin.** MCP:n README/ROADMAP viittaa tiedostoihin/hakemistoihin joita ei ole julkisessa puussa:
  - [ ] `bench/` + `bench/RESULTS.md` + `bench/HTTP_RESULTS.md`
  - [ ] `tools/nurlfmt/`
  - [ ] `tools/nurl-lsp/`
  - [ ] `tools/nurlpkg/`
  - [ ] `BORROW.md`
  - [ ] `docs/MEMORY.md`
  - [ ] `docs/spec.md`
  - [ ] `.github/workflows/ci.yml` (CI näkyvissä `main`-HEADissä)
  - [ ] Vaihtoehto: jos `Improvements`-branchia ei mergetä, **laske dokumentaatio takaisin** siihen mitä on oikeasti shipattu.

- [ ] **Julkaise reprodusoitavat benchmark-skriptit.**
  - [ ] `bench/run.sh` (yhden komennon ajo)
  - [ ] Lähdetiedostot per kieli (NURL/Python/Rust/Node, ja Go kun asennettu)
  - [ ] CI-job kiinteällä speksillä (esim. GitHub Actions `ubuntu-latest` 2-vCPU) joka kirjoittaa taulukon versioituun tiedostoon
  - [ ] Tavoite: kuka tahansa contributor saa `make bench`-ajolla 20 %:n tarkkuudella julkaistut luvut
  - [ ] HTTP-bench `oha 1.8.0`: dokumentoi 8-worker poolin koko ja se että C=10 piikki johtuu pool-koosta, ei yleisestä paremmuudesta hyperiin nähden

- [ ] **Hanki yksi ulkoinen contributor jonka PR koskee kääntäjää.** Bus factor 1 on dominoiva riski; kunnes toinen ihminen on mergennyt ei-triviaalin compiler-muutoksen, kaikki muu insinöörityö riippuu yhdestä henkilöstä.

## Tier 2 — kunnollisen kielen hygienia

- [ ] **Aja HTTP/2 + WebSocket interop-suite oikeita työkaluja vasten** ("offline RFC-vector verification" = unit test, ei interop):
  - [ ] `h2spec v2.4.0` (146 conformance casea RFC 7540 + RFC 7541 HPACK vasten)
  - [ ] `autobahn-testsuite` (WebSocket)
  - [ ] Konteksti: CVE-2023-44487 ("HTTP/2 Rapid Reset"), CVE-2019-9511…9518 -klusteri, CVE-2026-23918 (Apache `mod_http2` double-free) — RFC-appendix-vektorit eivät kata näitä

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

- [ ] **Poista "non-human readable" -framing.** Marketing-haava.
  - [ ] Kielen oikeat ominaisuudet (regular grammar, local semantics, deterministic compilation) tekevät siitä **helpommin** ihmis-reviewattavan
  - [ ] Lean into that — älä piiloutta että LLM "voi tuottaa" jotain mitä ihminen ei voi lukea

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
