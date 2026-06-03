import { ShieldCheck } from "lucide-react";

export function VigilantLogo({ className = "" }: { className?: string }) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <div className="relative grid h-8 w-8 place-items-center rounded-md border border-teal/40 bg-teal/10">
        <ShieldCheck className="h-4 w-4 text-teal" />
        <span className="absolute inset-0 rounded-md bg-teal/10 blur-md" aria-hidden />
      </div>
      <div className="leading-tight">
        <div className="font-mono text-[15px] font-semibold tracking-wider text-foreground">
          VIGILANT
        </div>
        <div className="font-mono text-[9px] uppercase tracking-[0.25em] text-muted-foreground">
          Onchain Insurance
        </div>
      </div>
    </div>
  );
}
