"use client";

import Link from "next/link";
import { useAccount, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { AddressText } from "@/components/ui/address";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Container } from "@/components/layout/container";
import { ConnectWalletButton } from "@/components/workspace/connect-wallet-button";
import { demoDistributorAbi } from "@/lib/abi/demo-distributor";
import { MAINNET_CHAIN_ID, MAINNET_DEPLOYMENT } from "@/lib/deployment";

export default function DemoPage() {
  const { address, isConnected, chainId } = useAccount();
  const onMonad = isConnected && chainId === MAINNET_CHAIN_ID;

  const {
    data: claimed,
    isLoading: isClaimedLoading,
    refetch: refetchClaimed,
  } = useReadContract({
    address: MAINNET_DEPLOYMENT.addresses.demoDistributor,
    abi: demoDistributorAbi,
    functionName: "claimed",
    args: address ? [address] : undefined,
    query: { enabled: onMonad && Boolean(address) },
  });

  const { writeContractAsync, isPending: isClaiming, data: txHash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  async function handleClaim() {
    await writeContractAsync({
      address: MAINNET_DEPLOYMENT.addresses.demoDistributor,
      abi: demoDistributorAbi,
      functionName: "claimDemoBundle",
    });
    await refetchClaimed();
  }

  return (
    <Container className="py-16">
      <h1 className="font-display text-2xl font-medium text-(--color-heading)">Demo</h1>
      <Card className="mt-6">
        <p className="text-sm text-(--color-body)">
          Claims 200 of each of the five real TIDYR demo tokens from the deployed
          DemoDistributor contract on Monad mainnet — one real transaction, real gas, one claim
          per address. Not a simulation.
        </p>
        <p className="mt-3">
          <AddressText
            value={MAINNET_DEPLOYMENT.addresses.demoDistributor}
            explorerUrl={`https://monadscan.com/address/${MAINNET_DEPLOYMENT.addresses.demoDistributor}`}
          />
        </p>
      </Card>

      <Card className="mt-6 flex flex-col gap-4">
        {!isConnected ? (
          <>
            <p className="text-sm text-(--color-body)">
              Connect a wallet on Monad mainnet to claim.
            </p>
            <div>
              <ConnectWalletButton />
            </div>
          </>
        ) : !onMonad ? (
          <>
            <p className="text-sm text-(--color-body)">Switch to Monad mainnet to claim.</p>
            <div>
              <ConnectWalletButton />
            </div>
          </>
        ) : isClaimedLoading ? (
          <p className="text-sm text-(--color-body)">Checking claim status…</p>
        ) : claimed || isConfirmed ? (
          <>
            <div className="flex items-center gap-2">
              <Badge tone="success">Claimed</Badge>
              <span className="text-sm text-(--color-body)">
                This address already holds the demo bundle.
              </span>
            </div>
            <div>
              <Link href="/app/wallets">
                <Button>Go clean it up in Wallets</Button>
              </Link>
            </div>
          </>
        ) : (
          <>
            <p className="text-sm text-(--color-body)">
              Connected as <AddressText value={address!} chars={4} />. Claim once to receive 200
              of each demo token, then head to Wallets to scan, plan, review, sign, and execute a
              real cleanup against them.
            </p>
            <div>
              <Button disabled={isClaiming || isConfirming} onClick={() => void handleClaim()}>
                {isClaiming
                  ? "Confirm in wallet…"
                  : isConfirming
                    ? "Claiming…"
                    : "Claim demo bundle"}
              </Button>
            </div>
          </>
        )}
      </Card>
    </Container>
  );
}
