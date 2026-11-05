// The one piece of the Workers runtime module the AI connector uses, for tests that run in Node.
export class WorkerEntrypoint<Env> {
  protected ctx: ExecutionContext;
  protected env: Env;
  constructor(ctx: ExecutionContext, env: Env) {
    this.ctx = ctx;
    this.env = env;
  }
}
