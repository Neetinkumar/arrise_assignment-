# arrise_assignment-

DevOps Terraform assignment: multi-instance EC2 provisioning, remote state &
locking, multi-account IAM/cross-account access, least-privilege policy
writing, and a Terraform bug fix.

See [NOTES.md](NOTES.md) for the written answers and [terraform/](terraform/)
for the implementation.

## Task 1 — Multi-Instance EC2 Provisioning

Create a Terraform module that provisions 5 EC2 instances, each with a
different instance type, root volume type, root volume size, and key pair.
Requirements:

- Drive all 5 instances from a single input variable (don't write 5 separate
  hardcoded resource blocks).
- At least one instance must use io1 or io2 storage.
- Tag every instance with Name, Environment, and Owner.
- Add a lifecycle block preventing accidental deletion of one specific
  instance of your choosing, and explain in NOTES.md which one and why.
- Output a map of instance name → instance ID and instance name → private IP.

## Task 2 — Remote State & Locking

Task 1's module currently has no backend configured. Add:

- An S3 backend for remote state, with a DynamoDB table for state locking.
- A short explanation of what happens today (with local state) if two people
  run `apply` at the same time, and how your backend change prevents that.

## Task 3 — Multi-Account IAM & Cross-Account Access

**Account A (000000000000):**

- Group `group1` for CLI/programmatic-only access. Members: `engine`, `ci`.
- Group `group2` for full console + CLI access. Members: two named users of
  your choice.
- `roleA`: administrative access to all AWS services except IAM.
- `roleB`: a role whose only permission is to assume a role in Account B.

**Account B (111111111111):**

- `roleC`: full access to a single named S3 bucket, assumable only by
  `roleB` from Account A — not by anything else in Account A.

In NOTES.md, answer directly:

- Would you actually give `engine` and `ci` IAM users with access keys in a
  real production setup, or would you do something different? Explain.
- In `roleC`'s trust policy, why does it matter whether you trust the whole
  Account A root vs. `roleB`'s specific ARN?

## Task 4 — Least-Privilege Policy Writing

Write a custom IAM policy (not a managed policy like `PowerUserAccess`) for
the `ci` user from Task 3, scoped to only what a CI pipeline actually needs
to do the following — nothing more:

- Push a Docker image to a specific ECR repository.
- Deploy a new task definition to a specific ECS service.
- Read (not write) a specific S3 bucket used for build artifacts.

Write the policy JSON and explain in NOTES.md what you deliberately left out
and why.

## Task 5 — Find and Fix the Bug

Below is a Terraform snippet meant to let `roleB` (Account A) assume `roleC`
(Account B). It's broken. Fix it and explain in NOTES.md, in your own words,
exactly why it was failing.

```hcl
data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:user/roleB"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:*"
      Resource = "*"
    }]
  })
}
```

(There are two separate issues here — one in the trust policy, one in the
permissions policy. Find both.)