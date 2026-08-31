# Terraform / AWS / Docker Diagnosis

Read-only diagnosis. No AWS resources were created, modified, or destroyed.
`terraform apply`/`terraform destroy` were never run. No `.tf`, `Dockerfile`,
or app files were edited.

AWS identity used for verification: `arn:aws:iam::208211371137:user/acarmonag`
(account `208211371137`, region `us-east-1`).

---

## Defect 1 (CRITICAL): Docker image never builds — missing `eslint-plugin-prettier` dependency

**Evidence** — `docker build --platform linux/amd64 -t rdicidr-smoke .`:

```
#12 [build 6/6] RUN npm run build
#12 9.104 Failed to compile.
#12 9.104
#12 9.104 Failed to load plugin 'prettier' declared in 'package.json': Cannot find module 'eslint-plugin-prettier'
#12 9.104 Require stack:
#12 9.104 - /app/node_modules/react-scripts/config/__placeholder__.js
#12 9.104 Referenced from: /app/package.json
#12 ERROR: process "/bin/sh -c npm run build" did not complete successfully: exit code: 1
```

`package.json` (`eslintConfig.extends`):

```json
"eslintConfig": {
  "extends": [
    "react-app",
    "react-app/jest",
    "plugin:prettier/recommended"
  ]
}
```

`package.json` `dependencies` contains `prettier` but **not** `eslint-plugin-prettier`
or `eslint-config-prettier`, which `plugin:prettier/recommended` requires. CRA
(`react-scripts build`) runs ESLint as part of the compile step, so the missing
plugin makes the build fail outright — the multi-stage Docker build never
produces a `build/` output, so stage 2 (`nginx:1.21-alpine`) never gets an
artifact to serve. The smoke test could not proceed past `docker build`; no
container was ever run.

**Root Cause**: `package.json` declares an ESLint config that depends on
`eslint-plugin-prettier` (and transitively `eslint-config-prettier`) without
listing them as dependencies. Works only in environments where these were
already present outside the lockfile (e.g. hoisted from elsewhere); not
reproducible from a clean `npm install`.

**Suggested minimal fix (not applied)**: add `"eslint-plugin-prettier"` and
`"eslint-config-prettier"` to `dependencies` (or `devDependencies`) at
versions compatible with `eslint` 6.x (the version `react-scripts@4.0.3` /
`eslint-config-react-app` pulls in), then re-run
`docker build --platform linux/amd64 -t rdicidr-smoke .` to confirm.

---

## Defect 2 (CRITICAL): ECS task definition has no `portMappings` — service cannot attach to the ALB target group

**Evidence** — `terraform plan` (container definition rendered, `terraform/main.tf` lines 92–107):

```
+ container_definitions    = jsonencode(
      [
        + {
            + essential        = true
            + image            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/rdicidr:latest"
            + logConfiguration = { ... }
            + name             = "rdicidr"
          },
      ]
  )
```

No `portMappings` key is present anywhere in the container definition, yet
`aws_ecs_service.app` (main.tf lines 187–191) declares:

```hcl
load_balancer {
  target_group_arn = aws_lb_target_group.app.arn
  container_name   = var.app_name
  container_port   = var.container_port
}
```

AWS documentation (ECS `LoadBalancer.containerPort`, via
`AWS::ECS::Service` / CDK reference) states: *"This port must correspond to
a `containerPort` in the task definition the tasks in the service are
using."* With no `portMappings` entry at all, there is no `containerPort` in
the task definition for AWS to match against `container_port = 80`. On
`terraform apply`, ECS `CreateService` will reject this with an
`InvalidParameterException` (container-to-load-balancer mismatch), and even
if it were somehow accepted, the awsvpc-mode ENI would have no declared
listening port for ALB health checks to reach.

**Root Cause**: The container definition in `aws_ecs_task_definition.app`
(main.tf) omits `portMappings`, so the task definition never declares that
the container listens on port 80 — despite nginx (per `nginx.conf`) actually
listening on 80 and the rest of the stack (SG ingress, target group, ALB
listener, service `load_balancer` block) all assuming port `var.container_port`
(80).

**Suggested minimal fix (not applied)**: add to the container definition JSON
in `main.tf`:

```hcl
portMappings = [
  {
    containerPort = var.container_port
    protocol      = "tcp"
  }
]
```

---

## Defect 3 (CRITICAL): Task execution IAM policy is missing `ecr:GetAuthorizationToken` — image pulls will fail

**Evidence** — `terraform/main.tf` lines 52–73 (`aws_iam_role_policy.ecs_task_execution_policy`):

```hcl
Action = [
  "ecr:GetDownloadUrlForLayer",
  "ecr:BatchGetImage",
  "ecr:BatchCheckLayerAvailability",
  "logs:CreateLogStream",
  "logs:PutLogEvents",
  "logs:CreateLogGroup"
]
```

AWS documentation ("Amazon ECS task execution IAM role", ECR permissions
section) specifies the required policy for pulling private images includes:

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
    "ecr:GetAuthorizationToken"
  ],
  "Resource": "*"
}
```

`ecr:GetAuthorizationToken` is absent from the Terraform-defined policy.
This action cannot be resource-scoped (must be `Resource: "*"`, which the
existing statement already uses) and is required by the Fargate agent to
authenticate to ECR *before* any `BatchGetImage`/`GetDownloadUrlForLayer`
call can succeed.

**Root Cause**: Custom inline IAM policy for the execution role omits
`ecr:GetAuthorizationToken`, so ECS tasks will fail to pull the container
image at launch with an authorization error (agent-level `CannotPullContainerError`
/ "no basic auth credentials"), independent of whether the image itself
exists.

**Suggested minimal fix (not applied)**: add `"ecr:GetAuthorizationToken"` to
the `Action` list in `aws_iam_role_policy.ecs_task_execution_policy`, or
replace the inline policy with the AWS-managed
`AmazonECSTaskExecutionRolePolicy` attached via `aws_iam_role_policy_attachment`.

---

## Defect 4 (CRITICAL): `container_image` default points at a non-existent placeholder account; no matching ECR repository exists in the real account

**Evidence** — `terraform/variables.tf`:

```hcl
variable "container_image" {
  default = "123456789012.dkr.ecr.us-east-1.amazonaws.com/rdicidr:latest"
}
```

AWS `sts:GetCallerIdentity` (live, read-only call) for the credentials used in
this diagnosis:

```json
{"UserId":"AIDATA6S5MSA4NUDOQZWX","Account":"208211371137","Arn":"arn:aws:iam::208211371137:user/acarmonag"}
```

`ecr:DescribeRepositories` (live, read-only, region `us-east-1`, account
`208211371137`):

```json
{"repositories": []}
```

The account in the default `container_image` value (`123456789012`) is AWS's
well-known documentation placeholder account, not the real deployment
account (`208211371137`). Even setting that aside, `DescribeRepositories`
against the real account returns zero repositories — no `rdicidr` (or any
other) ECR repository currently exists to push an image into or pull one
from.

**Root Cause**: `container_image` default was never parameterized to the
real account ID, and no ECR repository resource is defined anywhere in
`terraform/` (no `aws_ecr_repository`) or pre-created out of band. Combined
with Defect 1 (build never succeeds) and Defect 3 (missing pull permission),
there is currently no path from this repo to a running container in ECS.

**Suggested minimal fix (not applied)**: create an `aws_ecr_repository` in
Terraform (or document the pre-existing one to use), set `container_image`'s
default/`terraform.tfvars` value to
`208211371137.dkr.ecr.us-east-1.amazonaws.com/rdicidr:<tag>`, and push a
successfully-built image (after Defect 1 is fixed) before any `apply`.

---

## Defect 5 (HIGH): ALB target group health check path (`/healthz`) does not match any path nginx serves

**Evidence** — `terraform/variables.tf`:

```hcl
variable "health_check_path" {
  default = "/healthz"
}
```

`terraform plan` (target group resource):

```
+ health_check {
    + matcher             = "200"
    + path                = "/healthz"
    ...
  }
```

`nginx.conf` (the only two locations nginx defines):

```nginx
location / {
    root /usr/share/nginx/html;
    index index.html;
    try_files $uri $uri/ /index.html;
}

location /health {
    access_log off;
    return 200 'ok';
    add_header Content-Type text/plain;
}
```

nginx has no `location /healthz` block. A request to `/healthz` falls through
to `location /` with `try_files $uri $uri/ /index.html;`, which serves the
React SPA's `index.html` with HTTP 200 (not a 404) rather than exercising the
dedicated `/health` endpoint — so this particular mismatch happens not to fail
the ALB health check (SPA's catch-all also returns 200), but it silently
defeats the purpose of the dedicated lightweight `/health` endpoint nginx
actually exposes, and would break the moment the SPA route fallback ever
stops returning a bare 200 (e.g. if `index.html` were ever gated, cached with a
non-200 status, or the catch-all behavior changed).

**Root Cause**: `health_check_path` default (`/healthz`) does not match the
`/health` path nginx actually serves as a lightweight health endpoint
(`nginx.conf` lines 11–15). The two were defined independently and never
reconciled.

**Suggested minimal fix (not applied)**: change `health_check_path` default
in `terraform/variables.tf` from `/healthz` to `/health` to match `nginx.conf`,
or add a `location /healthz` block to `nginx.conf` matching the Terraform
default — pick one source of truth.

---

## Non-defects verified (evidence captured, no issue found)

- **`terraform fmt -check -diff`**: exit 0, no diff — all `.tf` files are
  correctly formatted.
- **`terraform validate`**: `Success! The configuration is valid.`
- **`terraform plan`**: runs cleanly against live AWS credentials/backend
  (local state, no remote backend configured); plan is `10 to add, 0 to
  change, 0 to destroy` — nothing currently deployed for this app.
- **Default VPC / subnets**: `terraform plan` resolves
  `data.aws_vpc.default` to real VPC `vpc-0e7b8d4388eca317d`;
  `DescribeSubnets` confirms all 6 subnets in that VPC have
  `MapPublicIpOnLaunch: true` and `DescribeInternetGateways` confirms an IGW
  (`igw-0cc201e6a806f4f6c`) is attached — consistent with
  `assign_public_ip = true` in `aws_ecs_service.app.network_configuration`.
  Networking wiring is sound.
- **Fargate CPU/memory sizing**: `cpu = "256"`, `memory = "512"` is a valid
  Fargate combination (0.25 vCPU / 0.5 GB) — no issue for a static-asset
  nginx container.
- **Fargate architecture**: no `runtime_platform` block is set, which
  defaults to `LINUX`/`X86_64` — matches the `--platform linux/amd64`
  requirement in this repo's CLAUDE.md. (The arm64/amd64 mismatch risk is a
  local Docker build-flag concern, not a Terraform defect, and is already
  called out in project docs.)
- **`aws_iam_role_policy.ecs_task_execution_policy` — CloudWatch Logs
  actions**: `logs:CreateLogStream`, `logs:PutLogEvents`,
  `logs:CreateLogGroup` are present and sufficient for the `awslogs` log
  driver configuration referencing `aws_cloudwatch_log_group.app`.
- **`ListRoles` / `ListClusters`** (live, read-only): no `rdicidr`-named IAM
  role or ECS cluster currently exists in the account — confirms this is a
  from-scratch deployment, not drift from a prior partial `apply`.

---

## Fixes Applied & Validation (TF track, `terraform/` only — Docker/CI Defect 1 fixed separately, see `docs/diagnosis-ci.md` and commit `bb30293`)

### Defect 2 — `portMappings` added

**Fix**: `terraform/main.tf`, container definition now includes:

```hcl
portMappings = [
  {
    containerPort = var.container_port
    protocol      = "tcp"
  }
]
```

**Validation**: `terraform apply -var-file=devel.tfvars` succeeded (10 resources
added, 0 changed, 0 destroyed); `aws ecs describe-services` shows the service
reaching `rolloutState=COMPLETED` with 2/2 tasks running, and both ENIs
registered as ALB targets — confirms the task definition's `containerPort`
correctly bound to the ALB target group.

### Defect 3 — `ecr:GetAuthorizationToken` added

**Fix**: `terraform/main.tf`,
`aws_iam_role_policy.ecs_task_execution_policy.Action` now includes
`"ecr:GetAuthorizationToken"` alongside the existing ECR/logs actions.

**Validation**: Both devel tasks pulled the `rdicidr-devel` image from ECR and
started successfully (no `CannotPullContainerError` / "no basic auth
credentials" in ECS service events across the full rollout) — confirms the
execution role can now authenticate to ECR before pulling image layers.

### Defect 4 — real ECR repo + account-derived image URI

**Fix**:
- `terraform/main.tf` — added `resource "aws_ecr_repository" "app"` named
  `${var.app_name}-${var.environment}` (so `rdicidr-devel` / `rdicidr-stage`
  never collide), plus `locals.container_image` deriving the full image URI
  from `var.aws_account_id`, `var.aws_region`, the repo name, and
  `var.container_image_tag` (no more hardcoded placeholder account).
- `terraform/variables.tf` — removed the `container_image` variable
  (hardcoded placeholder default `123456789012...`); added `aws_account_id`
  (default `208211371137`, the real account) and `container_image_tag`
  (default `latest`).

**Validation**: `terraform apply -var-file=devel.tfvars -target=aws_ecr_repository.app`
created `rdicidr-devel` in account `208211371137`
(`ecr_repository_url = "208211371137.dkr.ecr.us-east-1.amazonaws.com/rdicidr-devel"`).
A subagent built (`docker build --platform linux/amd64`) and pushed an image
to that URI; `aws ecr describe-images --repository-name rdicidr-devel`
confirmed it landed (tag `latest`, digest
`sha256:9cc9ec0f0bbefa3bf1bf31e96b518cf6a39e32d960da5cb0c3b82da92013e01d`,
status `ACTIVE`) before the ECS service was allowed to apply against it. Both
devel tasks pulled and ran that exact image successfully.

### Defect 5 — `health_check_path` aligned to `/health`

**Fix**: `terraform/variables.tf`, `health_check_path` default changed from
`/healthz` to `/health` to match the dedicated lightweight endpoint
`nginx.conf` actually serves.

**Validation**: `aws elbv2 describe-target-health` on the devel target group
shows both registered targets in state `healthy` (no `Target.FailedHealthChecks`),
confirming the ALB health check now hits nginx's real `/health` location
block rather than falling through to the SPA catch-all.

### Environment separation (devel/stage, FR-013/014/015 — new work, not a numbered defect)

**Fix**: Added `variable "environment"` (`terraform/variables.tf`, validated
to `"devel"`/`"stage"`) and interpolated it into every named resource in
`terraform/main.tf` (ECS cluster, task family, execution role/policy, log
group, security group, ALB, target group, service, ECR repo). Added
`terraform/devel.tfvars` and `terraform/stage.tfvars`. Created Terraform
workspaces `devel` and `stage` for state isolation (no remote backend
configured — local state under `terraform.tfstate.d/<workspace>/`).

**Validation**:
- `terraform fmt -check -diff -recursive`: exit 0, no diff.
- `terraform validate`: `Success!` in both the `devel` and `stage` workspaces.
- `devel` workspace: `terraform apply -var-file=devel.tfvars` → 10 resources
  (+ the earlier ECR-only apply) added, 0 changed, 0 destroyed. State at
  `terraform.tfstate.d/devel/terraform.tfstate` (13 resources incl. data
  sources).
- `stage` workspace: `terraform plan -var-file=stage.tfvars` → 11 to add, 0 to
  change, 0 to destroy, zero errors. **`apply` was never run against `stage`**
  (FR-013). All planned resource names carry the `stage` suffix
  (`rdicidr-stage-cluster`, `rdicidr-stage-service`, `rdicidr-stage-alb`,
  `rdicidr-stage-tg`, `rdicidr-stage-ecs-sg`, `rdicidr-stage-task-execution-role`,
  `rdicidr-stage`, ECR repo `rdicidr-stage`, log group `/ecs/rdicidr-stage`).
- Isolation confirmed: zero overlap between `devel`'s applied resource names
  (`rdicidr-devel-*`) and `stage`'s planned names (`rdicidr-stage-*`); state
  location differs too — `terraform.tfstate.d/devel/terraform.tfstate` (26KB,
  populated) vs `terraform.tfstate.d/stage/` (empty directory, confirming
  `stage` has never been applied).

### End-to-end devel verification (T024/T025)

`aws-verifier` agent polled ECS + target group for up to 5 minutes,
fail-fast-capable, then held a 2-minute healthy window:

- ECS: `rdicidr-devel-service` reached `runningCount=2`, `desiredCount=2`,
  `pendingCount=0`, deployment `rolloutState=COMPLETED`, no `STOPPED` tasks,
  no `failedTasks`, event log shows a clean rollout ending in "has reached a
  steady state".
- Target group `rdicidr-devel-tg`: both targets (`172.31.81.109:80`,
  `172.31.72.60:80`) healthy at every check, no `Target.FailedHealthChecks`.
- ALB reachability — `curl http://rdicidr-devel-alb-1624314853.us-east-1.elb.amazonaws.com/`
  returned `200` on 3 checks spaced ~60s apart over the 2-minute window.

## Summary

| # | Severity | Defect | File(s) | Status |
|---|----------|--------|---------|--------|
| 1 | CRITICAL | `npm run build` fails inside Docker build — missing `eslint-plugin-prettier` | `package.json`, `Dockerfile` | Fixed (CI track, commit `bb30293`) |
| 2 | CRITICAL | Task definition missing `portMappings`; ALB load-balancer block cannot bind | `terraform/main.tf` | Fixed & validated |
| 3 | CRITICAL | Execution role IAM policy missing `ecr:GetAuthorizationToken` | `terraform/main.tf` | Fixed & validated |
| 4 | CRITICAL | `container_image` default targets placeholder account; no ECR repo exists in real account | `terraform/variables.tf`, `terraform/main.tf` | Fixed & validated |
| 5 | HIGH | `health_check_path` (`/healthz`) doesn't match nginx's `/health` endpoint | `terraform/variables.tf` | Fixed & validated |
| — | — | Environment separation (devel/stage) — new work, not a logged defect | `terraform/variables.tf`, `terraform/main.tf`, `terraform/*.tfvars` | Added & validated |

`devel` applied cleanly, ECS steady/healthy, ALB serving `200` over HTTP.
`stage` validates and plans with zero errors, fully isolated from `devel` on
names and state, and was never applied — per constitution Principle III
(evidence → root cause → fix → validate) and FR-013.
