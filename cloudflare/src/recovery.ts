// recovery.ts — pure recovery policy for the container proxy.
//
// Deliberately free of any `cloudflare:workers` / `@cloudflare/containers`
// import so it can be unit-tested under plain Node (the Container subclass in
// index.ts can't be imported outside the Workers runtime). index.ts owns the
// I/O (fetch / destroy / request buffering); this module owns the decision.
//
// Background: when the nurlapi process is alive but no longer listening on its
// port, the @cloudflare/containers proxy returns a 500 whose body names the
// cause but never recycles the instance, so the wedge is permanent. We read
// that body to tell the recoverable proxy failures apart from a genuine 500
// emitted by the nurlapi app itself.

// Substrings (matched case-insensitively) in a 500 body.
//   wedged    — the DO's picture of the instance is wrong, so the instance
//               must be torn down before a retry can help:
//               * "The container is not listening in the TCP address …" —
//                 alive but the server stopped accepting; the DO never
//                 re-checks the port on its own.
//               * "The container is not running, consider calling start()" —
//                 the DO proxied to an instance that no longer exists (seen
//                 fleet-wide during the v0.37.0 image rollout, surfaced to
//                 users as a 500 because this policy didn't know the string).
//                 destroy() clears the stale state; the retry cold-starts.
//   transient — instance is mid-restart; a plain retry suffices.
export const WEDGE_MARKERS: readonly string[] = [
  "is not listening",
  "not listening in the tcp address",
  "is not running",
  "consider calling start",
];
export const TRANSIENT_MARKERS: readonly string[] = [
  "network connection lost",
  "suddenly disconnected",
  "failed to start container",
];

export type ProxyVerdict = "wedged" | "transient" | "app";

// Classify a 500 body. "app" = a real 500 from nurlapi (pass through); the
// others come from the container proxy layer and are recoverable.
export function classifyError(body: string): ProxyVerdict {
  const b = body.toLowerCase();
  if (WEDGE_MARKERS.some((m) => b.includes(m))) return "wedged";
  if (TRANSIENT_MARKERS.some((m) => b.includes(m))) return "transient";
  return "app";
}

export type RecoveryAction = "return" | "retry" | "recycle";

// Decide what the fetch loop should do after one proxy attempt.
//   return  — hand `res` back to the caller (success, app 500, or retries spent)
//   recycle — destroy the wedged instance, then retry on a fresh one
//   retry   — re-issue the request without a teardown (transient restart)
export function decideAction(
  status: number,
  body: string,
  attempt: number,
  maxRecycles: number,
): RecoveryAction {
  if (status !== 500 || attempt >= maxRecycles) return "return";
  const verdict = classifyError(body);
  if (verdict === "app") return "return";
  if (verdict === "wedged") return "recycle";
  return "retry";
}

// Deploy-stamp policy. With no NURL_DEPLOY_ID (self-hosted, local dev)
// nothing ever recycles. With one set:
//   * a KNOWN, differing build stamp recycles every time — converges to
//     a match once the image rollout has completed;
//   * a MISSING stamp (image predates stamping, or was built without
//     the arg) recycles at most ONCE per deploy id (`recycledFor` is
//     what the DO remembers) — bootstraps the first stamped deploy onto
//     a live unstamped instance without risking a permanent recycle
//     loop against a misconfigured image.
export function stampAction(
  deployId: string | undefined | null,
  buildId: string | undefined | null,
  recycledFor: string | undefined | null,
): "recycle" | "skip" {
  if (!deployId) return "skip";
  if (buildId) return buildId !== deployId ? "recycle" : "skip";
  return recycledFor === deployId ? "skip" : "recycle";
}
