import { Copy, ExternalLink } from "lucide-react";
import { truncate } from "@/lib/format";
import { explorerAddr } from "@/lib/somnia";
import { toast } from "sonner";

export function Mono({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <span className={`mono tabular ${className}`}>{children}</span>;
}

export function Address({
  value,
  link = true,
  copy = true,
  className = "",
}: {
  value?: string | null;
  link?: boolean;
  copy?: boolean;
  className?: string;
}) {
  if (!value) return <Mono className={`text-muted-foreground ${className}`}>—</Mono>;
  return (
    <span className={`inline-flex items-center gap-1.5 ${className}`}>
      <Mono className="text-foreground/90">{truncate(value)}</Mono>
      {copy && (
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault();
            navigator.clipboard.writeText(value);
            toast.success("Copied");
          }}
          className="text-muted-foreground transition hover:text-teal"
          aria-label="Copy address"
        >
          <Copy className="h-3 w-3" />
        </button>
      )}
      {link && (
        <a
          href={explorerAddr(value)}
          target="_blank"
          rel="noreferrer"
          className="text-muted-foreground transition hover:text-teal"
          aria-label="View on explorer"
        >
          <ExternalLink className="h-3 w-3" />
        </a>
      )}
    </span>
  );
}

export function Hash({ value }: { value?: string | null }) {
  return <Mono className="text-foreground/80">{truncate(value, 8, 6)}</Mono>;
}
