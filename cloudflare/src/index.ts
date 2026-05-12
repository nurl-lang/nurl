import { Container, getContainer } from "@cloudflare/containers";

export class NurlContainer extends Container<Env> {
  defaultPort = 8000;
  sleepAfter = "10m";
  // Forward all env vars the API container needs here if any.
  envVars = {
    NURL_API_URL: this.env.NURL_API_URL,
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Singleton: one container instance routes all requests.
    // For horizontal scaling use getRandom / idFromName with a key.
    const container = getContainer(env.NURL_CONTAINER);
    return container.fetch(request);
  },
} satisfies ExportedHandler<Env>;
