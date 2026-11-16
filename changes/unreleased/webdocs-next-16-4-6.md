### Security

- **The documentation site is built with Next.js 16.4.6.** 16.4.3 is inside the range of GHSA-mfr8-8qww-v76h (information disclosure across root params when a `'use cache'` function is called through `unstable_cache()`, moderate), which `pnpm audit` in CI refused. Only `next` and its `@next/*` packages change in the lockfile.
