# CI Workflow Diagnosis

Read-only diagnosis of `.github/workflows/ci.yaml` against required triggers/jobs, the
repo's branch discipline (`.specify/memory/constitution.md` Principle IV), and local
reproduction of every pipeline command. Node used for reproduction: v15.5.1 (matches
`package.json` `engines.node`), npm 7.3.0, on macOS/arm64 (commands are POSIX-portable so
results transfer to the `ubuntu-latest` runner used by the workflow). No files were
modified except this report.

---

## Defect 1: `eslint-plugin-prettier` is referenced but not installed — breaks `lint` and `build` jobs

**Evidence**

```
$ npm run lint
> rdicidr@0.1.0 lint
> eslint ./src/

Oops! Something went wrong! :(

ESLint: 7.29.0

ESLint couldn't find the plugin "eslint-plugin-prettier".
...
The plugin "eslint-plugin-prettier" was referenced from the config file in "package.json".
npm ERR! code 2
```

```
$ CI=true npm run build
> rdicidr@0.1.0 build
> react-scripts build

Creating an optimized production build...
Failed to compile.

Failed to load plugin 'prettier' declared in 'package.json': Cannot find module 'eslint-plugin-prettier'
Require stack:
- .../node_modules/react-scripts/config/__placeholder__.js
Referenced from: .../package.json
npm ERR! code 1
```

`package.json` `eslintConfig.extends` includes `"plugin:prettier/recommended"`:

```json
"eslintConfig": {
  "extends": ["react-app", "react-app/jest", "plugin:prettier/recommended"]
}
```

Confirmed via `ls node_modules | grep -i eslint-plugin-prettier` (no match) and
`grep -n "eslint-plugin-prettier" package.json package-lock.json` (no match in either
file) after a clean `npm ci`. The package is not a dependency, devDependency, or a
transitive dependency in the lockfile.

**Root cause**

`eslintConfig.extends` requires `eslint-plugin-prettier` (and `eslint-config-prettier`,
also absent) at lint/build time, but neither package is declared anywhere in
`package.json` (there is no `devDependencies` block at all) or present in
`package-lock.json`. CRA's build (`react-scripts build`) runs ESLint via
`ESLintWebpackPlugin` using the same `eslintConfig`, so the missing plugin fails both the
dedicated `lint` job and the `build` job.

**Suggested minimal fix (not applied)**

Add `eslint-plugin-prettier` and `eslint-config-prettier` as devDependencies (pinned to
versions compatible with ESLint 7.29.0, the version bundled by `react-scripts@4.0.3`), and
regenerate `package-lock.json`. Alternatively, if the prettier/eslint integration was
never intended, remove `"plugin:prettier/recommended"` from `eslintConfig.extends`.

---

## Defect 2: `npm run prettier` fails — 5 source files are not prettier-formatted

**Evidence**

```
$ npm run prettier
> rdicidr@0.1.0 prettier
> prettier -c ./src/

Checking formatting...
[warn] src/App.js
[warn] src/index.js
[warn] src/IPv4Addr.js
[warn] src/lib/ipv4.js
[warn] src/SubnetNumbersInput.js
[warn] Code style issues found in 5 files. Run Prettier with --write to fix.
npm ERR! code 1
```

**Root cause**

The five listed files under `src/` do not conform to Prettier's default formatting rules
(no `.prettierrc*` is present in the repo, so Prettier 3.3.1 defaults apply). `prettier -c`
exits non-zero on any mismatch, which fails the `Run formatter` step of the `lint` job.

**Suggested minimal fix (not applied)**

Run `npx prettier --write ./src/` locally and commit the reformatted files (or add a
`.prettierrc` if the intent was different formatting options than Prettier's defaults),
then re-run `npm run prettier` to confirm a clean pass.

---

## Defect 3: `App.test.js` "displays the API endpoint URL" fails — `REACT_APP_API_URL` is never set

**Evidence**

```
$ CI=true npm run test -- --watchAll=false
FAIL src/App.test.js
  ● displays the API endpoint URL

    expect(element).toHaveTextContent()

    Expected element to have text content:
      undefined
    Received:

      11 |   render(<App />);
      12 |   const apiUrlElement = screen.getByTestId("api-url");
    > 13 |   expect(apiUrlElement).toHaveTextContent(process.env.REACT_APP_API_URL);
         |                         ^

PASS src/tests/ipv4.test.js
Test Suites: 1 failed, 1 passed, 2 total
Tests:       1 failed, 10 passed, 11 total
npm ERR! code 1
```

`src/App.js` line 14 renders `process.env.REACT_APP_API_URL` into
`data-testid="api-url"`; `src/App.test.js` asserts the rendered text equals
`process.env.REACT_APP_API_URL` read at test time. No `.env`, `.env.local`, or
`.env.test` file exists in the repo (`ls -la .env*` → no matches), and the `test` job in
`ci.yaml` only sets `CI: true` — it does not set `REACT_APP_API_URL`. So
`process.env.REACT_APP_API_URL` is `undefined` both when `App` renders and when the
assertion evaluates it, and `toHaveTextContent(undefined)` fails against the actual
rendered (empty-string) content.

**Root cause**

The test asserts the rendered DOM text equals whatever `REACT_APP_API_URL` happens to be
at test-run time, but that variable is never defined in any environment the workflow (or
local dev, absent a manually exported var) actually uses. The test has no fixed expected
value to assert against, so it can never pass unless someone happens to export
`REACT_APP_API_URL` before invoking `npm test`.

**Suggested minimal fix (not applied)**

Either (a) set `REACT_APP_API_URL` to a fixed test value in the `test` job's `env:` block
in `ci.yaml` and assert against that literal string in `App.test.js`, or (b) change the
test to assert only that the element exists / is present (drop the value equality check)
if the URL is legitimately environment-dependent and not meant to be pinned in CI.

---

## Defect 4: `node-version: '14'` in the workflow contradicts `package.json` `engines.node` (`>=15.0.0 <16.0.0`)

**Evidence**

`ci.yaml` (all four jobs):
```yaml
- name: Set up Node.js
  uses: actions/setup-node@v3
  with:
    node-version: '14'
```

`package.json`:
```json
"engines": {
  "npm": ">=7.0.0 <8.0.0",
  "yarn": ">=1.22.0",
  "node": ">=15.0.0 <16.0.0"
}
```

Reproduced locally by installing Node 14.21.3 via nvm and checking the bundled npm:
```
$ nvm install 14.21.3
Now using node v14.21.3 (npm v6.14.18)
```
npm 6.14.18 does not satisfy the declared `engines.npm` constraint (`>=7.0.0 <8.0.0`)
either, and `actions/setup-node@v3` with `node-version: '14'` installs whatever npm ships
with that Node release (npm 6.x) — the workflow never installs/pins npm 7.

**Root cause**

`ci.yaml` was written against (or left over from) a Node 14 baseline, while
`package.json` `engines` was updated to require Node 15.x / npm 7.x (consistent with the
project's `CLAUDE.md`: "Node engine pinned: `>=15.0.0 <16.0.0`" and the Dockerfile's
`node:15-alpine` build stage). The workflow's Node/npm setup step was not updated to
match, so CI runs the whole pipeline (install, lint, test, build) under a Node/npm
combination the project's own `engines` field declares unsupported.

**Suggested minimal fix (not applied)**

Change `node-version: '14'` to a value inside `>=15.0.0 <16.0.0` (e.g. `'15'` or a pinned
`15.x.y`) in all four jobs, and if strict npm-version enforcement is desired, add an
explicit `npm install -g npm@7` step (or use `engine-strict=true` in `.npmrc`) since
`actions/setup-node` does not itself enforce `engines.npm`.

---

## Defect 5: `build` job's cache-restore key does not match the key `install` job saves under — `build` never gets `node_modules` and has no install step of its own

**Evidence**

`ci.yaml`, `install` job (saves) and `lint`/`test` jobs (restore) all use:
```yaml
key: node-modules-${{ hashFiles('package-lock.json') }}
```

`ci.yaml`, `build` job (restore) instead uses:
```yaml
key: deps-${{ hashFiles('package-lock.json') }}
```

No cache entry is ever saved under a `deps-...` key anywhere in the workflow, so
`actions/cache/restore@v3` in the `build` job will always miss. The `build` job has no
`npm install`/`npm ci` step — it only restores cache and then runs `npm run build`.
Reproduced the resulting failure mode locally by removing `node_modules` (simulating a
cache-restore miss) and running the exact command the `build` job runs:
```
$ mv node_modules /tmp/node_modules_saved && npm run build
> rdicidr@0.1.0 build
> react-scripts build

sh: react-scripts: command not found
npm ERR! code 127
```

**Root cause**

Copy/paste inconsistency: the cache key prefix `node-modules-` used by `install`/`lint`/
`test` was changed to `deps-` only in the `build` job's restore step, breaking the
save/restore key contract. Since `build` also has no fallback install step, a cache miss
is fatal rather than merely slow.

**Suggested minimal fix (not applied)**

Change the `build` job's restore key to `node-modules-${{ hashFiles('package-lock.json') }}`
to match the `install` job's save key. As defense in depth, consider also adding an
`npm ci` step to the `build` job (or any job that consumes the cache) so a cache miss
degrades to "slower" rather than "job fails outright."

---

## Defect 6: Trigger branch filters don't match this repo's branch-naming/discipline (constitution Principle IV)

**Evidence**

`ci.yaml`:
```yaml
on:
  push:
    branches:
      - main
      - 'feature-*'
  pull_request:
    branches:
      - main
```

`.specify/memory/constitution.md`, Principle IV ("Branch and Merge Discipline"):
> All new work MUST be done in `feature/` or `bugfix/` branches created from `devel`.
> Changes merge into `devel` only via pull request... Only `devel` may merge into
> `stage`...

Current repo branch (per `git status`/session context): `bugfix/agentic-repair` — a
pattern this workflow's triggers do not cover at all.

Per GitHub Actions' documented glob behavior (confirmed via search of GitHub's own docs
and community explainers): in branch filters, `*` matches any characters **except** `/`,
so `feature-*` matches a branch literally named `feature-foo` but does **not** match
`feature/foo` (the convention this repo actually uses, per `bugfix/` and presumably
`feature/` prefixes with a slash).

**Root cause**

The workflow's trigger branches (`main` for both push and PR, plus `feature-*` for push)
reflect a different branching model (trunk-based on `main`, hyphenated feature names)
than the one this repo's constitution mandates (`devel` as integration branch, `stage` as
promotion target, `feature/`- and `bugfix/`-prefixed slash-namespaced branches merging
into `devel` via PR). As written, CI never runs on `devel`, `stage`, `bugfix/*` branches,
or PRs targeting `devel` — meaning the actual repo workflow (bugfix branches merging to
devel) gets no CI coverage at all, and the `feature-*` filter wouldn't match this repo's
actual `feature/...` naming even if `feature` branches were in scope.

**Suggested minimal fix (not applied)**

Update `on.push.branches` and `on.pull_request.branches` to include `devel` and `stage`
(as the actual integration/promotion targets per Principle IV), and change `'feature-*'`
to `'feature/**'` and add `'bugfix/**'` so pushes to the branch types this repo actually
uses trigger CI. (Flagging as a question rather than asserted fact: whether CI is
*intended* to run on direct pushes to feature/bugfix branches, on PRs only, or both, is a
policy decision the constitution doesn't fully specify — worth confirming with whoever
owns the CI track before changing trigger scope.)

---

## Open questions / lower-confidence items (not asserted as defects)

- **No `permissions:` block** is set at the workflow or job level. Default
  `GITHUB_TOKEN` permissions depend on the repository/org setting
  ("Read and write" vs "Read only" default for new repos). Since this workflow only
  checks out code, installs, lints, tests, and builds (no deployment, no PR comments, no
  package publishing), the default token scope is very likely sufficient — but this
  wasn't verified against the actual repo/org token-permission setting, so it's a
  question rather than a confirmed defect.
- **`build` job depends only on `needs: [lint]`, not on `test`.** This means a broken
  `test` job does not block `build` from running (they run in parallel once `lint`
  finishes), so a build could report green while the test job is still red. Whether
  `build` is *intended* to gate on `test` passing wasn't specified anywhere I could find,
  so this is flagged as a design question, not asserted as a bug.
- **`npm install` vs `npm ci` in the `install` job.** `npm install` can update
  `package-lock.json` if `package.json` and the lockfile drift, and is generally
  discouraged in CI in favor of `npm ci` for reproducible installs. Locally, `npm ci`
  succeeded cleanly against the committed lockfile (see Defect 4 evidence section), so
  this isn't causing a current failure, but it's worth flagging as a reproducibility risk.
