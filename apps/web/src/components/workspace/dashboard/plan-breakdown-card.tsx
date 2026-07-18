import { Card } from "@/components/ui/card";
import type { PlanAction, PlanActionType } from "@/store/plan";

const TYPE_LABELS: Record<PlanActionType, string> = {
  sell: "Sell",
  consolidate: "Consolidate",
  discard: "Discard",
  burn: "Burn",
  revoke: "Revoke",
};

const TYPE_COLORS: Record<PlanActionType, string> = {
  sell: "bg-(--color-accent)",
  consolidate: "bg-(--color-accent-wash)",
  discard: "bg-(--color-border)",
  burn: "bg-(--color-heading)",
  revoke: "bg-(--color-muted)",
};

/** Real counts only — derived directly from the local plan store. */
export function PlanBreakdownCard({ actions }: { actions: PlanAction[] }) {
  const counts = actions.reduce(
    (acc, action) => {
      acc[action.type] = (acc[action.type] ?? 0) + 1;
      return acc;
    },
    {} as Partial<Record<PlanActionType, number>>,
  );
  const total = actions.length;
  const types = (Object.keys(counts) as PlanActionType[]).filter((t) => (counts[t] ?? 0) > 0);

  return (
    <Card className="flex flex-col gap-4">
      <h2 className="font-display text-base font-medium text-(--color-heading)">Plan breakdown</h2>

      {total === 0 ? (
        <p className="text-sm text-(--color-body)">
          No actions assigned yet. Assign an action to a token in the wallet workspace to see it
          here.
        </p>
      ) : (
        <>
          <div className="flex h-2.5 w-full overflow-hidden rounded-(--radius-pill) bg-(--color-frost)">
            {types.map((type) => (
              <span
                key={type}
                className={TYPE_COLORS[type]}
                style={{ width: `${((counts[type] ?? 0) / total) * 100}%` }}
              />
            ))}
          </div>
          <ul className="flex flex-col gap-2">
            {types.map((type) => (
              <li key={type} className="flex items-center justify-between text-sm">
                <span className="flex items-center gap-2 text-(--color-body)">
                  <span className={`h-2 w-2 rounded-full ${TYPE_COLORS[type]}`} />
                  {TYPE_LABELS[type]}
                </span>
                <span className="font-mono text-(--color-heading)">{counts[type]}</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </Card>
  );
}
