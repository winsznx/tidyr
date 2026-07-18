import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";

import { buildSweepPlans, type WalletPlanResult } from "@/lib/review/build-sweep-plans";
import {
  runPreconditionChecks,
  type PreconditionCheckResult,
} from "@/lib/review/precondition-checks";
import { verifyRoundTrip, type RoundTripCompareResult } from "@/lib/review/round-trip-compare";
import { usePlanStore } from "@/store/plan";

export interface WalletReview extends WalletPlanResult {
  roundTrip: RoundTripCompareResult | null;
  preconditions: PreconditionCheckResult | null;
}

/**
 * Composes the three read-only F11 layers for every wallet with a planned
 * action: (1) build a real SweepPlan + SweepManifest from live balances,
 * nonces, and DEX quotes; (2) the calldata encode/decode round-trip compare;
 * (3) live on-chain precondition checks. Nothing here signs or broadcasts
 * anything — every value comes from a `publicClient` read.
 */
export function useSweepReview() {
  const publicClient = usePublicClient();
  const actions = usePlanStore((s) => s.actions);

  return useQuery({
    queryKey: ["sweep-review", actions],
    enabled: Boolean(publicClient),
    queryFn: async (): Promise<WalletReview[]> => {
      if (!publicClient) throw new Error("not ready");

      const walletPlans = await buildSweepPlans(publicClient, actions);

      return Promise.all(
        walletPlans.map(async (result): Promise<WalletReview> => {
          if (!result.plan) {
            return { ...result, roundTrip: null, preconditions: null };
          }
          const roundTrip = verifyRoundTrip(result.plan);
          const preconditions = await runPreconditionChecks(publicClient, result.plan);
          return { ...result, roundTrip, preconditions };
        }),
      );
    },
    staleTime: 15_000,
  });
}
