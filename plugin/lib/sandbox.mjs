// A sandbox, such as Codex's default one, blocks the network and the person's config folder. These errors are what a
// blocked call throws, so a failed command can name the sandbox and not a wrong address.
const CODES = new Set(['EAI_AGAIN', 'ENOTFOUND', 'ENETUNREACH', 'EROFS', 'EACCES', 'EPERM']);

export const SANDBOX = 'If this runs in a sandbox, such as Codex\'s, run the command again outside the sandbox.';

/** True when `error`, or the cause a failed fetch gives, has a code a sandbox makes. */
export const sandboxed = error => CODES.has(error?.code) || CODES.has(error?.cause?.code);

/** `line`, then the sandbox line when the error could come from one. */
export const withSandbox = (line, error) => (sandboxed(error) ? `${line} ${SANDBOX}` : line);
