<!-- Assembled by coding-standards setup.sh — do not edit above the PROJECT-SPECIFIC marker -->

# AGENTS.md

Instructions for OpenAI Codex CLI.

## Environment

- Runs in a sandboxed container with an isolated filesystem.
- Network access may be restricted — do not assume external services are reachable.
- No interactive commands; all operations must be non-interactive and scriptable.

## Behavior

- Read project structure first (`ls`, read key files) before making any changes.
- Apply language-specific conventions by detecting file extensions.
- Run tests after implementation; do not mark a task complete if tests fail.
- Follow TDD for bug fixes and new features: write the failing test first.

## Approval Mode

**Suggest mode (default):** Explain the planned change before editing any file. Wait for confirmation.

**Auto mode:** Make changes directly with atomic commits and Conventional Commits messages (`type(scope): subject`). Each commit must represent one logical change.

## Constraints

- Do not modify generated files, lock files, or CI configuration unless explicitly requested.
- Do not add new dependencies without explaining why and listing alternatives considered.
- Make minimal changes — touch only the files required to satisfy the task.
- No secrets or credentials in any file; check before committing config files.
- If sync-standards reports customized files, pending updates are in `.standards-pending/`. See `.standards/docs/reference/merge-standards-prompt.md` to merge.

## Architecture

Dependencies point inward only: Domain ← Application ← Infrastructure ← Apps.

- **Domain:** Pure business logic. No external dependencies. Entities, value objects.
- **Application:** Orchestrates domain. Defines use cases and repository interfaces.
- **Infrastructure:** Implements interfaces. Handles DB, APIs, file systems.
- **Apps:** Entry points (CLI, web, workers). Depends on all inner layers.

SOLID principles mandatory. Violations require justification in code comments.
Validate inputs at boundaries. Fail fast; reject invalid state immediately.
Define typed custom errors in Domain. No generic exceptions.
Use structured logging with request ID, user ID, and operation context.
Secondary/derived subsystems (mirrors, indexes, sync, telemetry) are best-effort and error-isolated — a failure there must never break the primary write path.
When you catch-and-degrade, preserve and surface the original cause; never swallow it behind a generic "failed" message.

## Testing

TDD is mandatory. Red → Green → Refactor. Write failing tests before implementation code.
Coverage enforced in CI — blocks merge if violated:

- Domain / Core: 100%
- Application / Shell: 95%+
- Infrastructure: 95%+

Every bug fix must include a regression test.
Meet coverage with real tests — never add dead/unreachable branches to hit a number. For genuinely untestable boundaries (real filesystem/keychain/native APIs), keep the boundary thin, push logic into pure testable units, and flag the residual manual-verification step explicitly.
Run the build (e.g. `tsc -b`), not just typecheck — a narrow typecheck config often excludes test files and the project references that the full build compiles, so the build catches errors typecheck misses.
Mirror source structure: `src/domain/user.py` → `tests/domain/test_user.py`
Use descriptive test names: `test_should_raise_error_when_email_is_invalid`
Visual/snapshot baselines: regenerate via a CI dispatch job, never commit from a local run — rendered pixels are environment-specific and local baselines drift from CI.

## Security

P0/P1 block merge. P2 are warnings.

P0 (Critical): Never build SQL from user input — use parameterized queries. Never pass user input to `eval()`, `exec()`, `system()`. Never commit credentials. Never deserialize untrusted data via native serialization. Never ship default credentials. Verify auth on every request.

P1 (High): Encode all HTML output. No `innerHTML` with untrusted data. Validate URLs; block SSRF to internal IPs. Enable CSRF on state-changing endpoints. Secure cookie attributes (`Secure`, `HttpOnly`, `SameSite`). Regenerate session IDs after login. Use cryptographically secure random for tokens. Run dependency CVE scanning in CI. Enforce HTTPS/TLS. Configure CSP, HSTS, X-Content-Type-Options, X-Frame-Options. Never log passwords, tokens, or PII.

P2 (Warning): Missing rate limiting. Verbose errors in production. Unpinned dependencies. Missing encryption at rest.

Secrets scanning: run `git-secrets`, `truffleHog`, or `detect-secrets` in CI.
Add `.env` to `.gitignore`. Provide `.env.example` with placeholder values only.

## Naming Conventions

Use verbose, descriptive names. Avoid abbreviations. Functions are verbs. Classes are nouns.
Boolean variables: `is_`, `has_`, `should_`, `can_` prefixes.
Comments explain "why", never "what".

Python: `snake_case` variables/functions/modules, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, `_leading_underscore` private.
JavaScript/TypeScript: `camelCase` variables/functions, `PascalCase` classes/components/types, `kebab-case` files/dirs, `UPPER_SNAKE_CASE` constants.
Java/Kotlin: `camelCase` methods/variables, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, reverse-domain lowercase packages.
Ruby: `snake_case` methods/variables/files, `PascalCase` classes/modules, `?` suffix predicates, `!` suffix dangerous methods.
Rust/Zig: `snake_case` functions/variables, `PascalCase` types/structs/enums, `UPPER_SNAKE_CASE` constants.
Go: `camelCase` unexported identifiers, `PascalCase` exported functions/types/constants; `ALL_CAPS` not used (Go uses `PascalCase` for exported constants); short lowercase package names without underscores.
Elixir: `snake_case` functions/variables/atoms/files, `PascalCase` modules/aliases; `UPPER_SNAKE_CASE` not used (use module attributes `@name` instead); `?` suffix for predicates, `!` suffix for raising variants.

## Git Workflow

Conventional Commits: `type(scope): subject` — types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`.
Subject: imperative mood, ≤50 characters, no period.
Branch naming: `type/description` in kebab-case (e.g., `feature/user-authentication`, `fix/email-validation`).
One task = one branch = one PR. Work is not done until a PR exists. Prefer small, independently mergeable PRs, sequenced/stacked deliberately.
Feature branches from `main`. No direct pushes to `main`. Require one approval; all CI checks must pass.
PR merge loop: run the full local gate (`make ci`) first → open PR → wait for the automated reviewer → address every finding → all checks green (a partial pass is a fail) → squash-merge + delete branch. Never merge on a partial pass or before the automated review runs.
Run `gh pr create` from the feature worktree (or pass `--head`); the cwd's branch is what it opens.
Stacked PRs: retarget dependents to `main` before merging+deleting a base branch, or the dependents get closed.
Delete branches immediately after merge. Keep fewer than 10 active branches.
Never commit: secrets, build artifacts, `node_modules/`, `.env`, IDE files, OS files.
Always commit lock files (`package-lock.json`, `Gemfile.lock`, `Cargo.lock`, `uv.lock`).

## Documentation

Document all public APIs with language-standard formats (JSDoc, docstrings, rustdoc, JavaDoc, YARD). Include parameters, return values, errors, and examples.
Comments explain "why", never "what". Self-documenting code preferred.
Every package and app must have a README: purpose, installation, usage, configuration, development.
Create an ADR in `docs/adr/` for decisions affecting structure, dependencies, or significant technical choices.
Maintain `CHANGELOG.md` (Keep a Changelog format); update it for every user-facing change in a PR — UNLESS the project uses release automation (semantic-release, release-please, Changesets). With automation, release notes are generated (from Conventional Commits for commit-driven tools, or from per-PR changeset fragments for Changesets): do NOT hand-edit a shared `## [Unreleased]` block per PR (it causes merge conflicts under parallel work); rely on the generated notes or changeset fragments.
Track all work as GitHub Issues. Every `TODO`/`FIXME` must reference an issue: `# TODO(#42): description`.

## Language Standards

### Swift

Use Swift Package Manager (SPM). `Package.swift` for all dependencies. Swift 5.9+.
Format with `swiftformat` or `swift-format`. Lint with `swiftlint`. Treat warnings as errors in release builds.
Prefer `let` over `var`. Use `struct` for value types. Use `class` only when reference semantics needed.
Use protocols for interfaces. Prefer protocol-oriented design.
Use `Optional<T>` (`T?`) for nullable values. Avoid force unwrapping (`!`).
Use `enum` with associated values for typed errors. Use `Result<T, Error>` for functional error handling.
Use `[weak self]` in closures to prevent retain cycles.
Naming: `camelCase` functions/variables/constants, `PascalCase` types/protocols, `private` access control (no underscore prefix).
Test with `XCTest`. Use protocols for testability. 95% coverage minimum, 100% for domain.
Use `async`/`await` (Swift 5.5+). Use `actor` for thread-safe mutable state.
Security: Xcode static analyzer; GitHub Dependabot for SPM. Banned: `NSExpression` with user input, `Process` with unsanitized args. Use `SecRandomCopyBytes` for security contexts.

## Project Type

Separate data→view model transformations from view model→pixels rendering.
View model functions are pure: data in, data out, no side effects, no framework imports. Test without a display server.
Use a single source of truth for application state. State is immutable; produce new state, never mutate in place.
Side effects (API calls, storage) are isolated from state update logic.
Derive layout from semantic state (`LayoutMode` enum), not platform or user-agent detection.
Prefer `const` constructors and stateless components when possible.
Touch targets: 44×44pt minimum (iOS), 48×48dp (Android). All interactive elements need accessible labels.
Support keyboard navigation. Ensure focus order is logical. Maintain WCAG AA color contrast (4.5:1 normal text).
Avoid synchronous work on the main/UI thread. Paginate or virtualize large lists.
UI changes MUST be validated against reference designs in `assets/designs/<route-or-component>/<state>.png` — render, screenshot, diff. Human-gated approval; pixel-diff alone is too noisy to gate on. Full protocol in `proc-04 § 7 UI Change Validation`.

<!-- BEGIN PROJECT-SPECIFIC — DO NOT EDIT THIS LINE -->

<!-- Add project-specific instructions below this line. This section is preserved across re-assembly. -->

## Dust3D native Apple project

- The user's authorized implementation request enables direct local edits and validation. Do not require a second approval for those steps. Publishing, pushing, and merging remain separate user decisions; local delivery does not require a PR.
- This checkout uses `master` upstream and `codex/` implementation branches. Preserve the Qt application as a reference; native targets must never link it or Qt.
- Read `docs/coding-standards-audit.md`, `docs/cpp-standards.md`, and `docs/adr/0001-native-engine-and-viewer.md` for project-specific standards and current verification limits.
- C++ remains C++17. Preserve the root `.clang-format` (four spaces, WebKit braces, left pointer alignment, `.cc`/`.h`, existing `m_` members). No mass formatting or renaming of inherited code or vendored dependencies.
- New C++ uses RAII, explicit bounds checks, finite geometry values, checked conversions, and caught exceptions at the C ABI. Borrowed buffers remain valid only until their owning opaque handle is destroyed. Never expose STL types or C++ exceptions to Swift.
- Engine entry points are serialized because inherited UUID generation and engine globals are not proven thread-safe. Swift copies all buffers before releasing the handle. Swift 6 strict concurrency is required; rendering and observable UI state stay on the main actor.
- Use SwiftPM as the declarative build spec for this local macOS app and library. There is no hand-maintained Xcode project. Distribution signing and notarization are outside this prototype.
- Prefer semantic system colors, keyboard commands, accessible labels, and a small `NSViewRepresentable` boundary for Metal. This is a new viewer without a supplied reference design: inspect rendered UI; do not invent a pixel-diff baseline or block local completion on an unavailable reference.
- Run `make ci` for native build, tests, formatting, and Qt-link checks. Report measured coverage and manual GPU checks honestly. Do not claim the inherited engine meets the standards repo's 100% core coverage target.
- Canonical launch: `./script/build_and_run.sh`. Use `--verify` for process verification and `--build-only` to stage a bundle without opening it.

- Native engine implementation now belongs to `dalbrecht/dust3d-core`. Update the exact SwiftPM revision and committed `Package.resolved` through reviewed dependency PRs; never maintain a second native adapter here. Inherited Qt/reference trees remain uncompiled by native targets.
