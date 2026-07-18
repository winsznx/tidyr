import { Card } from "@/components/ui/card";
import { Container } from "@/components/layout/container";

const SECTIONS = [
  {
    title: "Closed adapter architecture",
    body: "SweepExecutor's constructor fixes exactly two adapter addresses — PancakeV2Adapter and UniswapV3Adapter. There is no registry, no owner-adjustable adapter list, and no way for a plan to name an arbitrary adapter address. A plan can only select AdapterKind.PANCAKE_V2 or AdapterKind.UNISWAP_V3.",
  },
  {
    title: "Permit2 witness binding",
    body: "Every signature is a Permit2 SignatureTransfer authorization witnessed to a specific executionPlanHash. A signature for one plan cannot be replayed against a different plan, a different chain, or a different SweepExecutor deployment.",
  },
  {
    title: "Exact amounts, never unlimited",
    body: "Permit2 permissions authorize exactly the token amounts a plan requires — never an open-ended allowance.",
  },
  {
    title: "Three-layer transaction review",
    body: "Before signing: (1) a canonical intent manifest is hashed, (2) the encoded calldata is decoded and compared field-by-field against that manifest, and (3) the transaction is simulated read-only against live chain state. Signing is blocked if any layer fails.",
  },
  {
    title: "Independently audited",
    body: "Contract security verification (fuzzing, invariants, adversarial mocks, fork tests, Slither triage, manual review, and an independent adversarial audit) is documented in PHASE_7_SECURITY_COMPLETION_REPORT.md and docs/threat-model.md.",
  },
];

export default function SecurityPage() {
  return (
    <Container className="py-16">
      <h1 className="font-display text-2xl font-medium text-(--color-heading)">Security model</h1>
      <div className="mt-8 space-y-4">
        {SECTIONS.map((s) => (
          <Card key={s.title}>
            <h2 className="font-display text-lg font-medium text-(--color-heading)">{s.title}</h2>
            <p className="mt-2 text-sm text-(--color-body)">{s.body}</p>
          </Card>
        ))}
      </div>
    </Container>
  );
}
