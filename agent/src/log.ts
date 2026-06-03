/// Tiny structured logger with timestamps and color, so the demo console reads well.
const c = {
  dim: (s: string) => `\x1b[2m${s}\x1b[0m`,
  teal: (s: string) => `\x1b[36m${s}\x1b[0m`,
  amber: (s: string) => `\x1b[33m${s}\x1b[0m`,
  red: (s: string) => `\x1b[31m${s}\x1b[0m`,
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  bold: (s: string) => `\x1b[1m${s}\x1b[0m`,
};

const ts = () => c.dim(new Date().toISOString().split("T")[1].replace("Z", ""));

export const log = {
  info: (msg: string) => console.log(`${ts()} ${c.teal("●")} ${msg}`),
  watch: (msg: string) => console.log(`${ts()} ${c.dim("◦")} ${c.dim(msg)}`),
  alert: (msg: string) => console.log(`${ts()} ${c.red("▲")} ${c.bold(c.red(msg))}`),
  act: (msg: string) => console.log(`${ts()} ${c.amber("⇒")} ${c.amber(msg)}`),
  ok: (msg: string) => console.log(`${ts()} ${c.green("✓")} ${c.green(msg)}`),
  banner: (msg: string) => console.log(`\n${c.bold(c.teal(msg))}\n`),
};
