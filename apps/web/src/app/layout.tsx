import type { Metadata } from "next";
import type { ReactNode } from "react";

import { ibmPlexMono, inter, spaceGrotesk } from "./fonts";
import { Providers } from "./providers";
import "@/styles/globals.css";

const siteOrigin = process.env["NEXT_PUBLIC_SITE_ORIGIN"] ?? "https://tidyr.app";

export const metadata: Metadata = {
  metadataBase: new URL(siteOrigin),
  title: {
    default: "TIDYR — Clean every Monad wallet without blindly signing",
    template: "%s · TIDYR",
  },
  description:
    "Scan every Monad wallet, choose what stays, sell or consolidate what does not, and understand every transaction before you sign.",
  applicationName: "TIDYR",
  icons: {
    icon: "/icon",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html
      lang="en"
      className={`${spaceGrotesk.variable} ${inter.variable} ${ibmPlexMono.variable}`}
    >
      <body className="font-sans">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
