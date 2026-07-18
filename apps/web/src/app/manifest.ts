import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "TIDYR",
    short_name: "TIDYR",
    description: "Clean every Monad wallet without blindly signing.",
    start_url: "/",
    display: "standalone",
    background_color: "#ffffff",
    theme_color: "#5e4cff",
    icons: [{ src: "/icon", sizes: "32x32", type: "image/png" }],
  };
}
