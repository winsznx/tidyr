import { IconCheck, IconGrid, IconSend, IconShield, IconWallet } from "@/components/ui/icon";

export const WORKSPACE_LINKS = [
  { href: "/app", label: "Workspace", icon: IconGrid },
  { href: "/app/wallets", label: "Wallets", icon: IconWallet },
  { href: "/app/review", label: "Review", icon: IconCheck },
  { href: "/app/execute", label: "Execute", icon: IconSend },
] as const;

export const SECONDARY_LINKS = [
  { href: "/security", label: "Security", icon: IconShield },
  { href: "/contracts", label: "Contracts", icon: IconGrid },
] as const;
