import type { ReactNode } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { ConnectWalletButton } from "@/components/workspace/connect-wallet-button";

export default function WorkspaceLayout({ children }: { children: ReactNode }) {
  return <AppShell headerRight={<ConnectWalletButton />}>{children}</AppShell>;
}
