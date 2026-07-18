import type { MetadataRoute } from "next";

const siteOrigin = process.env["NEXT_PUBLIC_SITE_ORIGIN"] ?? "https://tidyr.app";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: ["/app/execute", "/app/review"],
    },
    sitemap: `${siteOrigin}/sitemap.xml`,
  };
}
