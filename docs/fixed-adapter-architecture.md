# Fixed Adapter Architecture

This is a pointer document. TIDYR's closed, immutable-adapter architecture (the
RA-01 remediation superseding the earlier owner-managed adapter registry) is
documented in full at:

- **`docs/security-model.md` §1** ("Closed adapter set (no generic registry)") — the
  architectural summary: `SweepExecutor` resolves every swap to one of exactly two
  immutable addresses (`PANCAKE_V2_ADAPTER`, `UNISWAP_V3_ADAPTER`) fixed at
  construction, via a closed `SweepPlanLib.AdapterKind` enum.
- **`docs/approval-architecture.md`** — the approval/spender-safety angle
  specifically, including the full history of the CA-01/CA-02 → RA-01 →
  follow-up-hardening remediation sequence.
- **`packages/contracts/src/SweepExecutor.sol`**'s own contract-level doc comment —
  the authoritative, most detailed account, written at the point of definition.
- **`docs/threat-model.md`** threats 5-7 — the adapter-specific threat scenarios
  (malicious adapter implementation, compromised deployer, incorrect-but-legitimate
  adapter wired in) with their defenses and residual risks.

No separate content is duplicated here - this file exists only so that filename
references to "fixed adapter architecture" resolve to the correct location rather
than a 404.
