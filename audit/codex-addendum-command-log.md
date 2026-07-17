# Codex Security Addendum Command Log

Executed independently on 2026-07-17 from `/Users/mac/tidyr` unless noted.

| Command | Result |
| --- | --- |
| `pwd` | `/Users/mac/tidyr` |
| `git status --short` | Clean before audit; only permitted audit files added at completion |
| `git branch --show-current` | `fix/security-addendum-before-phase-7` |
| `git log --oneline --decorate --graph --all -30` | Three addendum commits above `124c0b9` |
| `git rev-list --count build/pre-frontend-production..fix/security-addendum-before-phase-7` | 3 |
| `git merge-base ...` | `124c0b9e5c2d2cfb511ae87f85408d6a664ba33d` |
| `git diff build/pre-frontend-production...fix/security-addendum-before-phase-7` | 25 files; 1,105 additions; 145 deletions |
| `git show --stat --format=fuller` for each commit | Inspected `ab3d458`, `9de4c84`, `0276555` independently |
| `git ls-files` | Tracked inventory inspected |
| `git status --ignored --short` | Only expected dependency/build outputs ignored |
| dependency/lock/submodule inspection | pnpm lock present; three pinned submodules resolved |
| `pnpm install --frozen-lockfile` (sandbox) | Failed: registry DNS and pnpm-store symlink permission |
| `pnpm install --frozen-lockfile` (approved external access) | PASS; lockfile current, pnpm 10.33.0 |
| `pnpm format` | PASS |
| `pnpm lint` | PASS |
| `pnpm typecheck` | PASS; 6 workspaces |
| `pnpm test` | PASS; 26 tests total, 0 skipped |
| `pnpm build` | PASS; 6 workspaces |
| `pnpm security:secrets` | PASS; no tracked secret patterns |
| `forge fmt --check` from repository root | Exit 0 but checked no Solidity paths; not valid evidence |
| `forge fmt --check` from `packages/contracts` | **FAIL**; formatting diffs in contracts/tests |
| `forge clean` | PASS |
| `forge build` | PASS; Solidity 0.8.17 and 0.8.26 units |
| `forge test` in sandbox | 89 passed, fork setup failed due blocked DNS; invariants included |
| fork test with approved network access | PASS; 2/2 using Monad RPC/live factory state |
| deterministic test selection | PASS; 87/87, 0 skipped |
| invariant test selection | PASS; 2/2; 8,192 calls each |
| `FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz.*'` | PASS; 3 properties × 2,048 runs |
| `slither . --exclude-dependencies` | **FAIL (255)**; analyzed 47 contracts, reported 37 results; key reports manually triaged |
| repository security-pattern searches | Completed across production, tests, apps, docs, and artifacts; vendored/generated trees separately classified |
| temporary inline hash mutation script | PASS for chain, executor, owner, recipient, output token, amount, adapter, route, minimum output, deadline, nonce, order; no file retained |

## Commit contents

- `ab3d458`: adds chain ID/executor to Solidity and TypeScript execution hashes, updates call sites/tests/vector.
- `9de4c84`: adds freeze booleans/modifiers/tests, changes gas snapshot, adds an unregistered-address Multicall3 test. It does **not** add explicit Multicall3 registration rejection.
- `0276555`: documentation/evidence/status changes only; contains inaccurate absence, formatting, tracking, and count claims documented in the findings.

## Failing commands

1. `cd packages/contracts && forge fmt --check`
2. `cd packages/contracts && slither . --exclude-dependencies`

The initial sandboxed install and all-in-one fork run failed only because network/store access was blocked; both applicable operations were rerun with authorized access, and the install/fork tests passed.

