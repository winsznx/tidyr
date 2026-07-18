import Link from "next/link";

import { Wordmark } from "@/components/brand/wordmark";
import { Container } from "@/components/layout/container";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";

export function Footer() {
  return (
    <footer className="border-t border-(--color-border) bg-(--color-canvas) py-12">
      <Container className="flex flex-col gap-8 sm:flex-row sm:justify-between">
        <div>
          <Wordmark />
          <p className="mt-2 max-w-xs text-sm text-(--color-body)">
            Multi-wallet cleanup for Monad mainnet, chain ID {MAINNET_DEPLOYMENT.chainId}.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-8 text-sm sm:grid-cols-3">
          <div>
            <p className="font-medium text-(--color-heading)">Product</p>
            <ul className="mt-2 space-y-1 text-(--color-body)">
              <li>
                <Link href="/app" className="hover:text-(--color-accent)">
                  Workspace
                </Link>
              </li>
              <li>
                <Link href="/demo" className="hover:text-(--color-accent)">
                  Demo
                </Link>
              </li>
            </ul>
          </div>
          <div>
            <p className="font-medium text-(--color-heading)">Docs</p>
            <ul className="mt-2 space-y-1 text-(--color-body)">
              <li>
                <Link href="/security" className="hover:text-(--color-accent)">
                  Security
                </Link>
              </li>
              <li>
                <Link href="/contracts" className="hover:text-(--color-accent)">
                  Contracts
                </Link>
              </li>
            </ul>
          </div>
          <div>
            <p className="font-medium text-(--color-heading)">Chain</p>
            <p className="mt-2 text-(--color-body)">Monad mainnet · 143</p>
          </div>
        </div>
      </Container>
    </footer>
  );
}
