import { useAccount } from "wagmi";

import { MAINNET_CHAIN_ID } from "./deployment";
import { isWalletConnectConfigured } from "./wagmi";

export type ConnectionState = "disconnected" | "connecting" | "wrong-chain" | "ready";

/**
 * Derives the app-level connection state documented in
 * docs/frontend-state-machine.md. PROVIDER_UNAVAILABLE is a separate,
 * static check (no injected provider AND no WalletConnect project ID
 * configured) surfaced by `hasAnyWalletPath` below, not folded into this.
 */
export function useConnectionState(): ConnectionState {
  const { isConnected, isConnecting, isReconnecting, chainId } = useAccount();

  if (isConnecting || isReconnecting) return "connecting";
  if (!isConnected) return "disconnected";
  if (chainId !== MAINNET_CHAIN_ID) return "wrong-chain";
  return "ready";
}

export function hasAnyWalletPath(): boolean {
  const hasInjectedProvider = typeof window !== "undefined" && Boolean(window.ethereum);
  return hasInjectedProvider || isWalletConnectConfigured;
}
