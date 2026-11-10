// A question the caller can fix, shared by the connector's answers and the memory and knowledge web they reach.

/** The connector's tools answer it as an error the AI reads; the web API, with this status. */
export class Refusal extends Error {
  readonly status: 400 | 403 | 404 | 501 | 503;
  constructor(message: string, status: 400 | 403 | 404 | 501 | 503 = 400) {
    super(message);
    this.status = status;
  }
}
