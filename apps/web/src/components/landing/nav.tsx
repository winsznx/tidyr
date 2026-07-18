import Link from "next/link";

import { Button } from "@/components/ui/button";
import { Wordmark } from "@/components/brand/wordmark";

const links = [
  { href: "#product", label: "Product" },
  { href: "#security", label: "Security" },
  { href: "/contracts", label: "Contracts" },
];

export function LandingNav() {
  return (
    <header className="sticky top-0 z-10 border-b border-(--color-border) bg-(--color-canvas)/90 backdrop-blur">
      <nav className="mx-auto flex h-16 max-w-(--container-content) items-center justify-between px-6">
        <Link href="/" className="flex items-center gap-2" aria-label="TIDYR home">
          <Wordmark />
        </Link>
        <ul className="hidden items-center gap-6 text-sm font-medium text-(--color-heading) sm:flex">
          {links.map((link) => (
            <li key={link.href}>
              <Link href={link.href} className="hover:text-(--color-accent)">
                {link.label}
              </Link>
            </li>
          ))}
        </ul>
        <Link href="/app">
          <Button size="md">Open TIDYR</Button>
        </Link>
      </nav>
    </header>
  );
}
