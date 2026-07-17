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
//   wedged    — instance reachable but server not accepting on the port; the
//               DO won't re-check on its own, so the instance must be torn down
//               ("The container is not listening in the TCP address …").
//   transient — instance is mid-restart; a plain retry suffices.
export const WEDGE_MARKERS: readonly string[] = [
  "is not listening",
  "not listening in the tcp address",
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

// Deploy-stamp policy: recycle only when BOTH identities are known and
// disagree. An image without a stamp (self-hosted, local dev) or a
// worker without NURL_DEPLOY_ID must never trigger recycling.
export function stampMismatch(
  deployId: string | undefined | null,
  buildId: string | undefined | null,
): boolean {
  return Boolean(deployId) && Boolean(buildId) && deployId !== buildId;
}
