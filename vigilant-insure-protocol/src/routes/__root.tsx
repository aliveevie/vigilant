import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  Outlet,
  createRootRouteWithContext,
  useRouter,
  HeadContent,
  Scripts,
} from "@tanstack/react-router";
import { useEffect, type ReactNode } from "react";
import { Toaster } from "sonner";

import appCss from "../styles.css?url";
import { reportLovableError } from "../lib/lovable-error-reporting";
import { Web3Providers } from "@/components/Web3Providers";
import { AppShell } from "@/components/AppShell";

function NotFoundComponent() {
  return (
    <div className="grid min-h-screen place-items-center px-4">
      <div className="text-center">
        <div className="mono text-xs uppercase tracking-[0.3em] text-muted-foreground">404</div>
        <h1 className="mt-2 text-2xl font-semibold">Route not found</h1>
        <a href="/" className="mono mt-4 inline-block text-sm text-teal hover:underline">
          ← Back to dashboard
        </a>
      </div>
    </div>
  );
}

function ErrorComponent({ error, reset }: { error: Error; reset: () => void }) {
  console.error(error);
  const router = useRouter();
  useEffect(() => {
    reportLovableError(error, { boundary: "tanstack_root_error_component" });
  }, [error]);
  return (
    <div className="grid min-h-screen place-items-center px-4">
      <div className="panel max-w-md p-6 text-center">
        <h1 className="text-lg font-semibold">Something went wrong</h1>
        <p className="mt-2 text-sm text-muted-foreground">{error.message}</p>
        <button
          onClick={() => {
            router.invalidate();
            reset();
          }}
          className="mono mt-4 rounded-md border border-teal/40 bg-teal/10 px-3 py-1.5 text-xs uppercase tracking-widest text-teal"
        >
          Retry
        </button>
      </div>
    </div>
  );
}

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "Vigilant — Onchain Insurance Protocol" },
      { name: "description", content: "Agentic onchain insurance on Somnia. Underwrite tranched capital, buy parametric exploit coverage, earn sentinel bounties." },
      { property: "og:title", content: "Vigilant — Onchain Insurance Protocol" },
      { property: "og:description", content: "Agentic onchain insurance on Somnia testnet." },
      { property: "og:type", content: "website" },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "preconnect", href: "https://fonts.googleapis.com" },
      { rel: "preconnect", href: "https://fonts.gstatic.com", crossOrigin: "anonymous" },
      {
        rel: "stylesheet",
        href: "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&display=swap",
      },
    ],
  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: NotFoundComponent,
  errorComponent: ErrorComponent,
});

function RootShell({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

function RootComponent() {
  const { queryClient } = Route.useRouteContext();
  return (
    <QueryClientProvider client={queryClient}>
      <Web3Providers>
        <AppShell />
        <Toaster
          theme="dark"
          position="bottom-right"
          toastOptions={{
            style: {
              background: "oklch(0.20 0.028 250)",
              border: "1px solid oklch(0.28 0.025 250)",
              color: "oklch(0.95 0.01 240)",
            },
          }}
        />
      </Web3Providers>
    </QueryClientProvider>
  );
}
