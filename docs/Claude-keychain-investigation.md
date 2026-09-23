# Claude startup Keychain prompts: source investigation

Date: 2026-09-23. QuotaNotch inspected at `276c37e`; ClaudeBar inspected at
`b7ebb4f23f30fda52081bdc371db6c87895d2d3d`, including history and the previously
credited reference commits. No user credentials, installed applications, or
local desktop state were inspected. No native application was run. This is a
source investigation, not proof of the user's exact runtime parent process.

## Confirmed missed upstream fix

[ClaudeBar #94](https://github.com/tddworks/ClaudeBar/issues/94) reports repeated
Keychain prompts in API mode despite Always Allow. The reporter confirmed an
update fixed their case. [Commit 251e0524](https://github.com/tddworks/ClaudeBar/commit/251e0524ba6ff34403ddaac593b0e3e9153b4be6)
replaced direct Security-framework credential access with `/usr/bin/security`
and added an in-memory credential cache. This change already exists in the
ClaudeBar revisions credited by QuotaNotch; it is not a new upstream change.

QuotaNotch `Core/ClaudeCredentialRepository.swift` still uses
`SecItemCopyMatching` and `SecItemUpdate`. Its loader reads both file and
Keychain candidates even after finding a valid file. ClaudeBar returns a file
credential before touching Keychain. QuotaNotch has quota-result caching but
no equivalent persistent-in-process credential cache across repository loads.
Renewal and compare-before-write checks perform several additional reads.

ClaudeBar later added a five-minute cache TTL and invalidation on authentication
failure in [01e710a6](https://github.com/tddworks/ClaudeBar/commit/01e710a62d58c19c42b4d545edc8431a9d2ec5b0).
An in-memory cache reduces repeat reads; it does **not** survive relaunch and
therefore cannot alone explain or fix a first-read prompt at every boot.

## Two different command-line operations

`security find-generic-password` reads a Keychain item. `claude /usage` launches
Claude Code to render usage. They are not interchangeable meanings of “CLI”.
Claude Code may itself spawn `security`; the displayed requester does not
identify its parent application.

QuotaNotch production wiring (`UI/QuotaNotchView.swift`, `Core/QuotaClient.swift`,
`Core/ClaudeQuotaProbe.swift`) always tries API first. Except for cancellation
and rate limiting, any failure can launch `ClaudeCLIQuotaFallback`, including
unavailable credentials and expired authentication. Thus a failed direct read
can be followed by another credential lookup inside Claude Code.

ClaudeBar has selectable CLI/API modes, defaults to CLI, and also supports
fallback. [Commit e360ca68](https://github.com/tddworks/ClaudeBar/commit/e360ca68272855cdcf738606b94087fc4b073c7d)
added a switch to disable CLI fallback because it could trigger prompts,
including SSH-key prompts. This is evidence against assuming that any use of
the upstream CLI path guarantees no dialogs; it is not proof that this commit
specifically fixed the user's Claude credential prompt.

## Launch differences, not established causes

| Detail | ClaudeBar | QuotaNotch |
| --- | --- | --- |
| Binary resolution | Login-shell PATH, cached, then common paths | App PATH, then a smaller hardcoded path list |
| Removed authentication environment | `CLAUDE_CODE_OAUTH_TOKEN` | Also `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` |
| Arguments | `/usage --allowed-tools ""` | `/usage --tools ""`, empty strict MCP config, hooks disabled |
| Working directory | Dedicated ClaudeBar Probe directory | Dedicated QuotaNotch ClaudeUsage directory |
| Terminal | PTY 160×50 | PTY 180×80 |
| Cleanup | Terminate parent, then kill if needed | Same basic parent-only strategy |

Binary selection and environment differences could change the credential path.
No evidence establishes PTY dimensions or the tool/MCP flags as the prompt
cause. Parent-only cleanup is shared, so it is not a demonstrated unique
QuotaNotch cause. Removing environment exclusions blindly could change billing
or account selection and is not an appropriate speculative fix.

## Limits and rejected explanations

- `/usr/bin/security` does not universally bypass item access control.
  [Apple's ACL documentation](https://developer.apple.com/documentation/security/access-control-lists)
  describes trusted application lists. A [Claude Code user report with process
  ancestry and controls](https://github.com/anthropics/claude-code/issues/77697)
  demonstrates `security` itself prompting for an item without the necessary
  trusted-application entry. That report is evidence of a possible condition,
  not verification of this user's item.
- [Claude Code #22144](https://github.com/anthropics/claude-code/issues/22144)
  reports token refresh recreating items and losing third-party permission.
  QuotaNotch's current writer updates data in place; no evidence here proves
  its `SecItemUpdate(kSecValueData)` resets the ACL. Do not claim it does.
- QuotaNotch packages use ad-hoc signatures. Rebuilding can change application
  identity, but an unchanged binary merely rebooting is not a rebuild. This
  alone is insufficient to explain every-boot behavior.
- Do not delete/recreate user credentials, broaden Keychain ACLs, or ask the
  user to repeatedly select Always Allow as a substitute for fixing access.

## Repair and verification scope

First address the confirmed integration gap: upstream file-first credential
selection, stable system-utility access, bounded in-memory caching with forced
reload on authentication failure, and current compact-JSON/hex readback support.
Preserve account-change checks and safe refresh persistence; do not copy the
old delete-and-recreate writer from the original fix (later upstream fixed it).

Separately make failure routing explicit, so credential denial does not blindly
start a second interactive credential reader. Do not mislabel denied reads as
signed out or claim removing monitoring is a successful fix.

Regression checks should cover valid-file/no-Keychain access, cache expiry and
auth invalidation, failed read classification, refresh/account changes, process
timeouts, and which fallback paths actually launch a process. A controlled
cloud Keychain fixture can test access identities with fake credentials, but
cannot establish this user's current ACL or prove their reboot popup gone.
No implementation or runtime-fix claim is made by this document.
