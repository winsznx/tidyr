import type { MetadataRoute } from "next";

const siteOrigin = process.env["NEXT_PUBLIC_SITE_ORIGIN"] ?? "https://tidyr.app";

export default function sitemap(): MetadataRoute.Sitemap {
  const routes = ["/", "/app", "/demo", "/security", "/contracts"];
  return routes.map((route) => ({
    url: `${siteOrigin}${route}`,
    lastModified: new Date(),
  }));
}
