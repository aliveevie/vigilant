import { toast } from "sonner";
import { explorerTx } from "@/lib/somnia";

export function txToast(label: string, hash?: `0x${string}`) {
  if (!hash) {
    toast.loading(label, { id: label });
    return;
  }
  toast.success(label, {
    id: label,
    description: (
      <a
        href={explorerTx(hash)}
        target="_blank"
        rel="noreferrer"
        className="mono text-xs text-teal underline-offset-2 hover:underline"
      >
        View tx ↗
      </a>
    ),
    duration: 8000,
  });
}

export function errToast(label: string, err: unknown) {
  const msg = err instanceof Error ? err.message : String(err);
  toast.error(label, { description: msg.slice(0, 240) });
}
