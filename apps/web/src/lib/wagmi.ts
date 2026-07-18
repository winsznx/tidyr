import { http, createConfig } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";

import { monadMainnet } from "./chain";

const walletConnectProjectId = process.env["NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID"];

/**
 * WalletConnect is only registered when a real project ID is configured.
 * Without one, the connector is silently omitted rather than shipped
 * half-configured — the wallet picker shows only what actually works,
 * per the "no fabricated capability" rule in frontend-integration-matrix.md.
 */
const connectors = [
  injected(),
  ...(walletConnectProjectId ? [walletConnect({ projectId: walletConnectProjectId })] : []),
];

export const wagmiConfig = createConfig({
  chains: [monadMainnet],
  connectors,
  transports: {
    [monadMainnet.id]: http(),
  },
  ssr: true,
});

export const isWalletConnectConfigured = Boolean(walletConnectProjectId);
