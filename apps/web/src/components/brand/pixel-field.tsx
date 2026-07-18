/**
 * The single decorative flourish in the system (design.md §"Imagery"),
 * reinterpreted for TIDYR: scattered wallet-fragment tiles that resolve into
 * an ordered grid left-to-right, echoing "messy wallets → tidy plan". Fixed,
 * deterministic tile positions (no Math.random) so server/client markup
 * matches exactly.
 */
const TILES: Array<{
  x: number;
  y: number;
  size: number;
  tone: "accent" | "wash" | "pale";
  jitter: number;
}> = [
  { x: 0, y: 0, size: 12, tone: "pale", jitter: 10 },
  { x: 1, y: 0, size: 8, tone: "wash", jitter: -6 },
  { x: 2, y: 0, size: 12, tone: "accent", jitter: 4 },
  { x: 3, y: 0, size: 12, tone: "accent", jitter: 0 },
  { x: 0, y: 1, size: 8, tone: "wash", jitter: -3 },
  { x: 1, y: 1, size: 12, tone: "pale", jitter: 8 },
  { x: 2, y: 1, size: 12, tone: "accent", jitter: 2 },
  { x: 3, y: 1, size: 8, tone: "accent", jitter: 0 },
  { x: 0, y: 2, size: 12, tone: "wash", jitter: 6 },
  { x: 1, y: 2, size: 8, tone: "pale", jitter: -4 },
  { x: 2, y: 2, size: 8, tone: "wash", jitter: 3 },
  { x: 3, y: 2, size: 12, tone: "accent", jitter: 0 },
  { x: 0, y: 3, size: 8, tone: "pale", jitter: 5 },
  { x: 1, y: 3, size: 12, tone: "accent", jitter: -8 },
  { x: 2, y: 3, size: 12, tone: "accent", jitter: 0 },
  { x: 3, y: 3, size: 8, tone: "wash", jitter: 2 },
];

const toneColor: Record<(typeof TILES)[number]["tone"], string> = {
  accent: "#5e4cff",
  wash: "#c8ccf3",
  pale: "#dfdbff",
};

export function PixelField({ className }: { className?: string }) {
  const cell = 28;
  return (
    <svg
      viewBox="0 0 112 112"
      className={className}
      role="img"
      aria-label="Decorative violet pixel-grid motif"
    >
      {TILES.map((tile, i) => {
        const settled = tile.x * cell + (cell - tile.size) / 2;
        const settledY = tile.y * cell + (cell - tile.size) / 2;
        const isColumn3or4Order = tile.x >= 2;
        const offset = isColumn3or4Order ? 0 : tile.jitter;
        return (
          <rect
            key={i}
            x={settled + offset}
            y={settledY + offset * 0.6}
            width={tile.size}
            height={tile.size}
            rx={2}
            fill={toneColor[tile.tone]}
          />
        );
      })}
    </svg>
  );
}
