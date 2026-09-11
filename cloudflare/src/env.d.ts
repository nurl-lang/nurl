// The deployment workflow supplies this build stamp with --var. Local runs
// omit it and skip image-adoption checks; resource bindings come from Wrangler.
interface Env {
  NURL_DEPLOY_ID?: string;
}
