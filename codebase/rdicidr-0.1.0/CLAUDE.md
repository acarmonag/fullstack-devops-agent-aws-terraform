# rdicidr — Project Instructions

## Constitution
Read `.specify/memory/constitution.md` before any repair/fix work. Governs: repair-not-rebuild, never disable checks, evidence-root cause-fix-validate, branch discipline, commit ownership.

## Stack
- React 17 SPA (`react-scripts` 4.0.3), CSS modules, CRA build to `build/`
- Served by nginx (`nginx.conf`) in production container
- Node engine pinned: `>=15.0.0 <16.0.0`
- Docker: multi-stage `node:15-alpine` build to `nginx:1.21-alpine` runtime
- Terraform (`terraform/`): AWS ECS Fargate, ALB, target group, CloudWatch logs

## Docker rule
Every `docker build` / `docker run` MUST use `--platform linux/amd64`. Fargate runs amd64; local machine is arm64 — mismatch causes silent exec-format failures.

## Repo map
- `src/` — app code. Core: `IPv4Addr.js`, `Netmask.js`, `Octet.js`, `SubnetNumbersInput.js`, `App.js`. Tests in `src/tests/` + `*.test.js` colocated.
- `terraform/` — `main.tf` (ECS cluster, task def, service, ALB, SG, IAM, CloudWatch), `variables.tf`, `outputs.tf`
- `Dockerfile`, `nginx.conf` — container build/serve
- `.specify/` — spec-kit workflow, constitution, templates
- `docs/` — project docs and diagnosis reports (create if missing)
- `.chat-history/log.md` — session log, see below

## Validation commands
- `npm run lint` — eslint on `./src/`
- `npm run prettier` — prettier check on `./src/`
- `npm test` — react-scripts test (CRA/jest)
- `npm run build` — production build
- `terraform fmt -check`, `terraform validate`, `terraform plan` — in `terraform/`
- `docker build --platform linux/amd64 -t rdicidr .` — container smoke build

## docs/ index
Create `docs/` if missing. Keep an index at `docs/README.md` linking generated docs (e.g. `docs/diagnosis-ci.md`, `docs/diagnosis-tf.md`).

# Chat History Logging (permanent, silent)

Applies to every session in this project.

## At session start
Read `.chat-history/log.md` if it exists. Use as prior context. Do not print or summarize it unless user asks.

## After each response
Silently append an entry to `.chat-history/log.md`, exact format below. Create `.chat-history/` and `log.md` if missing. Append only — never rewrite, never delete or edit previous entries, even across multiple sessions. Never ask for confirmation. Never announce the write.

```
---
- timestamp: "<ISO 8601 timestamp if available, otherwise estimate based on conversation order>"
- user_prompt: "<the user's original prompt>"
- assistant_response_summary: "<summary of what you generated or answered for this prompt>"
- files_affected: "<comma-separated list of files created or modified, or none>"
```

## Rules
- files_affected: only files explicitly created/modified during that response, else "none"
- Log every prompt/response pair, no skips
- assistant_response_summary: concise, specific (function names, endpoints, key decisions)
- Escape any embedded double-quotes/newlines in field values so file stays valid
- `.chat-history/` is never gitignored, regardless of what else gets ignored
