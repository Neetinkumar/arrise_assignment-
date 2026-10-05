# NOTES

Project layout:

```
terraform/
  versions.tf, providers.tf, variables.tf   - shared config
  main.tf, outputs.tf                       - Task 1 (EC2 instances)
  backend.tf                                - Task 2 (S3 + DynamoDB backend)
  bootstrap/                                 - Task 2 (one-off: creates the backend's bucket/table)
  iam.tf                                     - Task 3 (groups, users, roleA/roleB/roleC)
  policies/ci-policy.json.tpl + .example.json - Task 4 (least-privilege ci policy)
  task5/broken.tf.txt + fixed.tf             - Task 5 (bug fix + explanation)
```

All account IDs, ARNs, bucket names and key-pair names in the defaults are
placeholders (e.g. `000000000000`, `111111111111`, `my-app-build-artifacts`) -
swap them for real values before applying anything.

---

## Task 1 - which instance is protected, and why

`db-primary` (see `terraform/variables.tf`, `var.protected_instance_key`).

It's the only stateful, data-tier instance in the set - it's also the one
using `io2` storage, which is provisioned specifically for a database's IOPS
and durability needs. Losing `web-1`, `web-2`, `cache-1` or `app-1` to a
mistaken `terraform destroy`/plan is annoying but cheap to recover from
(they're stateless/replaceable from an AMI). Losing `db-primary` means losing
data, not just compute - so it's the one instance where `prevent_destroy`
earns its keep. Because `prevent_destroy` must be a literal value and can't
vary per-key inside one `for_each`, `db-primary` is provisioned from its own
`aws_instance.protected` resource block (still driven from the same
`var.instances` map) rather than a per-instance flag.

## Task 2 - local state race condition, and how the backend fixes it

**Today (local state):** Terraform's state file is just `terraform.tfstate`
on whoever's laptop runs `apply`. If two people run `apply` at roughly the
same time:

- There's no lock, so nothing stops both runs from reading state, computing a
  plan, and writing changes concurrently.
- Each person's local state file only reflects *their own* process's view of
  the world. Whichever one finishes (writes `terraform.tfstate`) last wins,
  silently overwriting the other's state - the "losing" run's changes become
  invisible to Terraform even though they were actually applied in AWS. State
  drifts from reality, and the next `plan` either tries to recreate resources
  that already exist (API errors / duplicate resources) or tries to destroy
  resources the other person just created.

**With the S3 + DynamoDB backend:** state lives in one shared S3 object
instead of N laptops, so there's a single source of truth both people read
from. DynamoDB provides the locking: before `apply` touches state, Terraform
writes a lock row (keyed by `LockID`) to the table; the second `apply` sees
the lock is held and blocks/fails fast instead of proceeding concurrently.
So the second person is forced to wait until the first finishes and releases
the lock, then runs against the now-current state - no silent overwrite, no
split-brain state.

## Task 3 - would you actually give `engine` and `ci` IAM users with access keys?

No, not in a real production setup.

- `ci` is a CI pipeline. Static, long-lived IAM access keys for a pipeline are
  a standing credential-leak risk (they end up in build logs, cached
  environments, or forgotten repo secrets, and don't rotate themselves). The
  real fix is OIDC federation: the CI provider (GitHub Actions, GitLab CI,
  etc.) assumes an IAM role directly via `sts:AssumeRoleWithWebIdentity`,
  scoped to that specific repo/branch via the trust policy's `sub` claim
  condition. No long-lived secret exists at all.
- `engine` reads like a service/application identity, not a human. If it's
  code running on EC2/ECS/Lambda, it should get its permissions via an
  instance profile / task role / execution role, which hands out short-lived
  credentials automatically - again, no access key to leak or rotate.

I implemented `engine` and `ci` as literal IAM users with access keys in
`iam.tf` because that's what the task explicitly asks for (and it's a
reasonable way to demonstrate the group1/group2 access-method distinction),
but in a real environment I'd replace both with role-based, keyless access as
above.

## Task 3 - roleC trust policy: whole Account A root vs. roleB's specific ARN

It matters because trusting the Account A root (`arn:aws:iam::000000000000:root`)
means **any** sufficiently-permissioned principal in Account A can assume
roleC - not just roleB. Any IAM user or role in Account A whose own policy
grants it `sts:AssumeRole` on roleC's ARN would be able to get into Account B
and touch that S3 bucket, regardless of whether that was ever the intent.
It turns "only roleB can reach this bucket" into "only Account A's own IAM
policies decide who can reach this bucket" - the access-control decision
silently moves from Account B (which owns the resource) back into Account A.

Trusting roleB's specific ARN (`arn:aws:iam::000000000000:role/roleB`)
instead means Account B's own trust policy is the enforcement point: only
that one role can assume roleC, full stop, independent of whatever IAM
policies get added in Account A later. That's the whole point of the
exercise's roleB -> roleC design, and it's what `iam.tf` implements
(`identifiers = [aws_iam_role.roleB.arn]`).

## Task 4 - what was deliberately left out of the `ci` policy, and why

See `terraform/policies/ci-policy.example.json` / `ci-policy.json.tpl`. Left out:

- **Any managed policy** (e.g. `PowerUserAccess`, `AmazonECS_FullAccess`,
  `AmazonEC2ContainerRegistryFullAccess`) - all of these grant far more than
  "push to one repo, deploy one service, read one bucket," including the
  ability to touch every other ECR repo, ECS service and S3 bucket in the
  account.
- **ECR admin/management actions** - `ecr:CreateRepository`,
  `ecr:DeleteRepository`, `ecr:SetRepositoryPolicy`, etc. CI pushes images;
  it doesn't need to create or delete repositories or change their policies.
- **ECS cluster/service management** - `ecs:CreateService`,
  `ecs:DeleteService`, `ecs:CreateCluster`, `ecs:DeleteCluster`. CI deploys a
  new revision to an *existing* service; it doesn't provision or tear down
  infrastructure.
- **`iam:PassRole` with `Resource: "*"`** - scoped to exactly the one ECS
  task execution role, with an `iam:PassedToService: ecs-tasks.amazonaws.com`
  condition, so `ci` can't pass some other, more privileged role to some
  other AWS service.
- **S3 write/delete on the artifacts bucket** - only `s3:GetObject` and
  `s3:ListBucket`. CI consumes build artifacts; it doesn't need to overwrite
  or delete them (the task says "read, not write").
- **`Resource: "*"` wherever AWS allows scoping it down** - the two
  exceptions are `ecr:GetAuthorizationToken`, `ecs:RegisterTaskDefinition`
  and `ecs:DescribeTaskDefinition`, which AWS simply does not support
  resource-level restriction for (they only accept `Resource: "*"` - not a
  looseness I chose, a hard API limitation).

## Task 5 - why the original snippet was broken

Two separate bugs, both in `terraform/task5/broken.tf.txt`:

1. **Trust policy principal was wrong.** It referenced
   `arn:aws:iam::000000000000:user/roleB` - an IAM *user* path - but roleB is
   an IAM *role* (created elsewhere as `aws_iam_role.roleB` / Task 3). That
   ARN points at a user named "roleB" that doesn't exist, so when the real
   roleB role tried to call `sts:AssumeRole` on roleC, AWS would deny it:
   nothing in roleC's trust policy actually names roleB's role ARN. Fixed by
   changing `user/roleB` to `role/roleB`.

2. **Permissions policy wasn't scoped to the named bucket.** The task asked
   for "full access to a single named S3 bucket," but the policy granted
   `"Action": "s3:*"` on `"Resource": "*"` - every bucket in Account B, not
   just the one in question. Fixed by scoping `Resource` to that bucket's ARN
   and its `/*` object ARN.

Both fixes are in `terraform/task5/fixed.tf`, and the same corrected pattern
is what's actually wired up in `terraform/iam.tf`.
