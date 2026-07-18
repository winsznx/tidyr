import { ImageResponse } from "next/og";

export const alt = "TIDYR — Clean every Monad wallet without blindly signing";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          backgroundColor: "#ffffff",
          padding: "64px",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div style={{ width: 28, height: 28, borderRadius: 6, background: "#5e4cff" }} />
          <div style={{ fontSize: 32, fontWeight: 600, color: "#36394a" }}>TIDYR</div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
          <div
            style={{
              fontSize: 56,
              fontWeight: 600,
              color: "#36394a",
              lineHeight: 1.05,
              letterSpacing: -1,
              maxWidth: 920,
            }}
          >
            Clean every Monad wallet without blindly signing.
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            {[12, 8, 12, 8].map((s, i) => (
              <div
                key={i}
                style={{
                  width: s,
                  height: s,
                  borderRadius: 2,
                  background: i % 2 === 0 ? "#5e4cff" : "#c8ccf3",
                }}
              />
            ))}
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <div style={{ width: 8, height: 8, borderRadius: 999, background: "#5e4cff" }} />
          <div style={{ fontSize: 20, color: "#666d80" }}>Live on Monad mainnet</div>
        </div>
      </div>
    ),
    { ...size },
  );
}
