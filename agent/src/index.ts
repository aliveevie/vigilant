import "dotenv/config";
import { Sentinel } from "./sentinel.js";
import { log } from "./log.js";
import type { Hex } from "viem";

async function main() {
  const pk = process.env.SENTINEL_PRIVATE_KEY as Hex | undefined;
  if (!pk || !pk.startsWith("0x")) {
    log.alert("SENTINEL_PRIVATE_KEY missing. Copy .env.example to .env and set a funded key.");
    process.exit(1);
  }

  const simulate = process.argv.includes("--simulate");
  const sentinel = new Sentinel(pk);
  await sentinel.start({ simulate });
}

main().catch((e) => {
  log.alert(`fatal: ${e?.message ?? e}`);
  process.exit(1);
});
