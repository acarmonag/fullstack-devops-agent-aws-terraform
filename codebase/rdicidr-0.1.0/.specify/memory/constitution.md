<!--
Sync Impact Report
Version change: none (template unfilled) → 1.0.0
Modified principles: n/a (initial ratification)
Added sections: Core Principles (I-V), Branching & Merge Policy, Ownership & Commit Boundaries, Defect Logging, Credential Handling, Governance
Removed sections: none
Templates requiring updates: none tracked in this repo beyond .specify/memory/constitution.md
Deferred TODOs: none
-->

# rdicidr Constitution

## Core Principles

### I. AI as Primary Engineer, Repair Not Rebuild
The AI agent acts as primary engineer on this codebase. Default action for any defect or
gap is repair of the existing implementation, never a rebuild or rewrite. Changes MUST be
minimal diffs — each changed line traces to an observed, evidenced defect. Speculative
refactors, unrelated cleanup, or rewrites-in-place of working code are prohibited outside
an explicit user request.
Rationale: minimal, traceable diffs keep review cheap and prevent silent scope creep in an
agent-driven workflow.

### II. Never Disable Checks to Pass
Tests, linters, type checks, CI gates, and build checks MUST NOT be disabled, skipped, or
weakened to make a change appear to pass. If a check is wrong, fix the check itself as its
own evidenced defect (see Principle III), not as a side effect of an unrelated change.
Rationale: disabling checks hides regressions and defeats the purpose of automated
verification.

### III. Evidence-Root Cause-Fix-Validate (NON-NEGOTIABLE)
Every defect fixed MUST follow, in order: (1) Evidence — capture the observed failure
(error text, failing test, log line); (2) Root Cause — identify the actual mechanism, not
a symptom; (3) Fix — minimal diff addressing the root cause; (4) Validate — a real run
(test execution, build, or manual invocation) confirming the fix. No success MUST be
claimed without runtime evidence attached to the claim.
Rationale: prevents guess-and-check fixes and unverifiable "looks correct" claims common
in agent-driven repair work.

### IV. Branch and Merge Discipline
All new work MUST be done in `feature/` or `bugfix/` branches created from `devel`.
Changes merge into `devel` only via pull request — direct pushes to `devel` are
prohibited. Only `devel` may merge into `stage`; no other branch may merge directly into
`stage`. Direct pushes to `stage` are prohibited. `origin` is the only remote and MUST
point to the user's own repository.
Rationale: enforces a single controlled promotion path and prevents untracked changes
landing on shared branches.

### V. Ownership and Commit Boundaries
Commits MUST include only files owned by the change being made. `specs/` and `.specify/`
are owned by the CI track and MUST NOT be committed by unrelated work. `.chat-history/`
is committed only at final merge, not on intermediate commits. `git pull --rebase` MUST
run before every push. `git add -A` MUST NOT be used — stage files explicitly by name.
Rationale: explicit staging prevents accidental inclusion of unrelated, generated, or
sensitive files into a commit.

## Defect Logging

Each defect fixed MUST be logged in `docs/diagnosis-<area>.md` with four sections:
evidence, root cause, fix, and validation. This log is independent of and in addition to
commit messages and PR descriptions.

## Credential Handling

Credentials, tokens, and secrets MUST NOT be read, printed, or committed at any point in
the workflow, including in logs, diagnosis files, or chat history. If a secret is
discovered exposed, treat it as its own defect: evidence (where found), root cause
(how it got there), fix (remove and rotate), validate (confirm removal and rotation).

## Governance

This constitution supersedes conflicting ad hoc practices for this repository. Amendments
require an explicit update to this file with a Sync Impact Report and a version bump
following semantic versioning: MAJOR for incompatible governance/principle removals or
redefinitions, MINOR for new principles or materially expanded guidance, PATCH for
wording/clarification only. The agent operates without asking clarifying questions during
execution: where an instruction is ambiguous, the agent states its assumption and
proceeds, logging the assumption where it affects a defect fix.

**Version**: 1.0.0 | **Ratified**: 2026-08-30 | **Last Amended**: 2026-08-30
