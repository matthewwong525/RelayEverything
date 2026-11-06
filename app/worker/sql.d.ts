// A migration file, bundled as its text by the Text rule in wrangler.spaces.jsonc.
declare module "*.sql" {
  const text: string;
  export default text;
}
