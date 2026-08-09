import { Container, getContainer } from "@cloudflare/containers";
import { decideAction, stampAction } from "./recovery";
import { downloadKey, extractArtifactTokens, shouldScanForArtifacts } from "./artifacts";

// ── Why this file has a custom fetch override ─────────────────────────────
//
// The playground container occasionally wedges: the nurlapi server process is
// still *alive* (so the Durable Object's view stays `running` + `'healthy'`)
// but is no longer accepting connections on port 8000 — e.g. after a heavy
// compile burst, an OOM that took a worker rather than PID 1, or a soft
// deadlock. In that state the @cloudflare/containers runtime never recovers
// on its own:
//
//   • startAndWaitForPorts() early-returns WITHOUT re-checking the port when
//     `state.status === 'healthy' && container.running` (container.ts), so it
//     never notices the server stopped listening; and
//   • containerFetch() catches the proxy failure and returns a 500 whose body
//     is "Error proxying request to container: The container is not listening
//     in the TCP address 10.0.0.1:8000" — but it does NOT mark the instance
//     unhealthy or restart it.
//
// So every subsequent request repeats the same failure forever, and since
// continuous traffic keeps renewActivityTimeout() alive the instance never
// even sleeps to recycle. A clean crash/OOM of PID 1 *does* self-heal (the DO
// sees `!running` and cold-starts), which is exactly why the stuck state is a
// hang, not a crash.
//
// The fix: detect that wedged-proxy 500, force-destroy the instance (so the
// next start spins up a fresh container), and replay the request. This makes
// any server-side wedge self-heal within a single request instead of becoming
// a sticky outage.

// How many times to recycle+retry before giving up and surfacing the error.
// (The classification policy lives in ./recovery, kept pure for unit testing.)
const MAX_RECYCLES = 2;

// How often (at most) to compare the running image's build stamp against
// the deployed one. A live instance under steady public traffic never
// idles long enough to recycle onto a new image on its own — this check
// makes deploys reach it deterministically, converging even when the
// image rollout finishes minutes after `wrangler deploy` (a premature
// recycle lands back on the old image, and the next check fires again).
const STAMP_CHECK_MS = 5 * 60_000;

export class NurlContainer extends Container<Env> {
  defaultPort = 8000;
  sleepAfter = "10m";
  // Forward all env vars the API container needs here if any.
  envVars = {
    NURL_API_URL: this.env.NURL_API_URL,
  };

  // The default onError rethrows; rethrowing from a lifecycle callback (e.g.
  // the one destroy() triggers) can poison the DO. Log and swallow instead.
  override onError(error: unknown): void {
    console.error("[nurl-container] lifecycle error:", error);
  }

  // Self-healing proxy — see the file header for the failure it recovers from.
  override async fetch(request: Request): Promise<Response> {
    // The container tunnel speaks plain HTTP (it is already secured by the
    // platform), and the runtime REJECTS container connections described as
    // https: "Connecting to a container using HTTPS is not currently
    // supported". containerFetch only rewrites its URL *string* — the
    // original Request it passes as fetch init still carries the https URL,
    // which newer runtime validation trips over. Normalize the scheme here,
    // before anything reaches the proxy.
    const httpUrl = request.url.replace(/^https:/, "http:");

    // Standard reverse-proxy contract: tell the origin what scheme the
    // CLIENT used, since the tunnel itself is always plain http. nurlapi
    // reads this when it builds absolute URLs (OAuth issuer/endpoints,
    // mcp.json snippets) so they say https://, not the tunnel's http://.
    const fwdHeaders = new Headers(request.headers);
    fwdHeaders.set("X-Forwarded-Proto", new URL(request.url).protocol.replace(":", ""));

    // WebSocket upgrades (the /pptws voice relay) can't be buffered or
    // replayed — proxy them straight through with no retry. Upgrades are
    // always GET, so a headers-only rebuild loses nothing.
    if ((request.headers.get("Upgrade") ?? "").toLowerCase() === "websocket") {
      return super.fetch(new Request(httpUrl, { headers: fwdHeaders }));
    }

    // Buffer the body once so the request can be replayed after a recycle.
    // Compile requests (POST /build*) carry the user's source and must
    // survive a retry; their bodies are small.
    const hasBody = request.method !== "GET" && request.method !== "HEAD";
    const bodyBuf = hasBody ? await request.arrayBuffer() : undefined;
    // redirect: "manual" — a reverse proxy must pass upstream redirects
    // THROUGH to the client, never follow them itself. The default
    // ("follow") made the container-port fetcher chase /authorize's 302
    // Location (https://claude.ai/…) through the container binding, and
    // the runtime rejects https on that path — which broke the whole
    // OAuth connect flow while every non-redirecting route worked.
    const replay = (): Request =>
      new Request(httpUrl, {
        method: request.method,
        headers: fwdHeaders,
        body: bodyBuf,
        redirect: "manual",
      });

    // Deploy-stamp adoption: /health reports the image's baked build_id;
    // when it differs from the Worker's NURL_DEPLOY_ID, this instance is
    // running a pre-deploy image — recycle it (throttled) so the request
    // is served by the new one.
    if (this.env.NURL_DEPLOY_ID) {
      const last = (await this.ctx.storage.get<number>("stampCheckAt")) ?? 0;
      if (Date.now() - last > STAMP_CHECK_MS) {
        await this.ctx.storage.put("stampCheckAt", Date.now());
        try {
          const h = await super.fetch(new Request("http://container/health"));
          const j = (await h.json()) as { build_id?: string };
          const recycledFor = await this.ctx.storage.get<string>("stampRecycledFor");
          if (stampAction(this.env.NURL_DEPLOY_ID, j.build_id, recycledFor) === "recycle") {
            await this.ctx.storage.put("stampRecycledFor", this.env.NURL_DEPLOY_ID);
            await this.recycle(
              `image build ${j.build_id || "?"} != deploy ${this.env.NURL_DEPLOY_ID}`,
            );
          }
        } catch {
          // Probe failure = the normal request path will deal with it.
        }
      }
    }

    for (let attempt = 0; ; attempt++) {
      let res: Response;
      try {
        res = await super.fetch(replay());
      } catch (e) {
        // The base fetch normally returns a 500 rather than throwing, but a
        // thrown error is just as much a proxy failure — recycle and retry.
        if (attempt >= MAX_RECYCLES) {
          const msg = e instanceof Error ? e.message : String(e);
          return new Response(`container unavailable after recovery: ${msg}\n`, {
            status: 502,
          });
        }
        await this.recycle("threw: " + (e instanceof Error ? e.message : String(e)));
        continue;
      }

      // Cheap exits first; only read the body for an unresolved 500.
      if (res.status !== 500 || attempt >= MAX_RECYCLES) return res;

      const action = decideAction(res.status, await res.clone().text(), attempt, MAX_RECYCLES);
      if (action === "return") return res; // a real 500 from nurlapi — pass through.
      if (action === "recycle") {
        // Alive-but-not-listening: the DO won't re-check the port on its own,
        // so tear the instance down — the retry's start spins a fresh one.
        await this.recycle("proxy reported container not listening");
      }
      // "retry" → the instance is already restarting; just re-issue.
    }
  }

  // Force-destroy the current instance so the next containerFetch starts a
  // fresh one. Never throws (destroy() routes through our swallowing onError,
  // but guard anyway so a failed teardown can't abort the retry loop).
  private async recycle(reason: string): Promise<void> {
    console.warn(`[nurl-container] recycling instance: ${reason}`);
    try {
      await this.destroy();
    } catch (e) {
      console.error("[nurl-container] destroy() during recycle failed:", e);
    }
  }
}

// Copy a set of build artifacts from the container's disk into R2. Runs in
// waitUntil, racing the instance's idle recycle — which it wins by minutes.
// Failures are logged and swallowed: mirroring is a durability upgrade, never
// a reason to fail the build that produced the artifacts.
async function mirrorArtifacts(
  tokens: string[],
  container: { fetch(request: Request): Promise<Response> },
  env: Env,
  origin: string,
): Promise<void> {
  await Promise.all(
    tokens.map(async (token) => {
      try {
        if (await env.NURL_ARTIFACTS.head(token)) return;
        const res = await container.fetch(new Request(`${origin}/download/${token}`));
        if (res.status !== 200) return;
        await env.NURL_ARTIFACTS.put(token, await res.arrayBuffer(), {
          httpMetadata: {
            contentType: res.headers.get("Content-Type") ?? "application/octet-stream",
          },
        });
      } catch (e) {
        console.error(`[nurl-artifacts] mirroring ${token} failed:`, e);
      }
    }),
  );
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // Singleton: one container instance routes all requests. The fetch
    // override above makes that instance self-heal, so a wedge recovers
    // within a request instead of becoming a sticky outage. For horizontal
    // scaling swap to getRandom(env.NURL_CONTAINER, N) (uses max_instances).
    const container = getContainer(env.NURL_CONTAINER);
    const url = new URL(request.url);

    // Artifact downloads are served R2-first: the container's build dirs die
    // with the instance (idle sleep, deploy adoption, wedge recovery), but a
    // mirrored artifact keeps its URL alive across generations — and an R2
    // hit doesn't wake a sleeping container at all. A miss falls through to
    // the container (covers the build→mirror completion window) and mirrors
    // what it finds, so even artifacts whose build-time mirror was missed
    // become durable on first download.
    const key = request.method === "GET" ? downloadKey(url.pathname) : null;
    if (key) {
      const stored = await env.NURL_ARTIFACTS.get(key);
      if (stored) {
        const headers = new Headers();
        stored.writeHttpMetadata(headers);
        if (!headers.has("Content-Type")) headers.set("Content-Type", "application/octet-stream");
        return new Response(stored.body, { status: 200, headers });
      }
      const res = await container.fetch(request);
      if (res.status !== 200) return res;
      const body = await res.arrayBuffer();
      ctx.waitUntil(
        env.NURL_ARTIFACTS.put(key, body, {
          httpMetadata: {
            contentType: res.headers.get("Content-Type") ?? "application/octet-stream",
          },
        }),
      );
      return new Response(body, res);
    }

    const res = await container.fetch(request);

    // Build responses (REST /build* and MCP tool calls alike) name the
    // artifacts they produced by /download/ URL. Mirror them to R2 now,
    // off the response path, before a recycle can take the disk with them.
    if (shouldScanForArtifacts(request.method, url.pathname) && res.status === 200) {
      const copy = res.clone();
      ctx.waitUntil(
        (async () => {
          const tokens = extractArtifactTokens(await copy.text());
          if (tokens.length > 0) await mirrorArtifacts(tokens, container, env, url.origin);
        })(),
      );
    }
    return res;
  },
} satisfies ExportedHandler<Env>;
