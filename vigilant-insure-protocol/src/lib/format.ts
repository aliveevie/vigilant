import { formatEther } from "viem";

export const truncate = (s?: string | null, head = 6, tail = 4) => {
  if (!s) return "—";
  if (s.length <= head + tail + 2) return s;
  return `${s.slice(0, head)}…${s.slice(-tail)}`;
};

export const fmtSTT = (wei?: bigint | null, digits = 4) => {
  if (wei === null || wei === undefined) return "—";
  const s = formatEther(wei);
  const [i, d = ""] = s.split(".");
  return d ? `${i}.${d.slice(0, digits).padEnd(digits, "0")}` : `${i}.${"0".repeat(digits)}`;
};

export const fmtBps = (bps?: number | bigint | null) => {
  if (bps === null || bps === undefined) return "—";
  const n = typeof bps === "bigint" ? Number(bps) : bps;
  return `${(n / 100).toFixed(2)}%`;
};

export const fmtPct = (n?: number | null) =>
  n === null || n === undefined ? "—" : `${n.toFixed(2)}%`;
