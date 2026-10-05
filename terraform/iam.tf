#######################################
# Task 3 - Multi-account IAM & cross-account access
#######################################

# ---- Account A: group1 (CLI/programmatic-only) ----
# "CLI/programmatic-only" is an access-METHOD distinction, not a permission
# scope: these users get no console login profile (no password) and only an
# access key. ci's permission scope is defined separately in Task 4's policy;
# engine's is intentionally left undefined since the assignment doesn't
# specify what engine itself needs to do - see NOTES.md.

resource "aws_iam_group" "group1" {
  name = "group1"
}

resource "aws_iam_user" "engine" {
  name = "engine"
}

resource "aws_iam_user" "ci" {
  name = "ci"
}

resource "aws_iam_group_membership" "group1_members" {
  name  = "group1-membership"
  group = aws_iam_group.group1.name
  users = [aws_iam_user.engine.name, aws_iam_user.ci.name]
}

resource "aws_iam_access_key" "engine" {
  user = aws_iam_user.engine.name
}

resource "aws_iam_access_key" "ci" {
  user = aws_iam_user.ci.name
}

# ci's actual permissions: the least-privilege policy from Task 4.
resource "aws_iam_user_policy" "ci_least_privilege" {
  name = "ci-least-privilege"
  user = aws_iam_user.ci.name
  policy = templatefile("${path.module}/policies/ci-policy.json.tpl", {
    ecr_repository_arn          = var.ecr_repository_arn
    ecs_service_arn             = var.ecs_service_arn
    ecs_task_execution_role_arn = var.ecs_task_execution_role_arn
    ci_artifacts_bucket_name    = var.ci_artifacts_bucket_name
  })
}

# ---- Account A: group2 (full console + CLI access) ----
# Both a console login profile AND an access key, for two named users.
# No permissions policy is attached here: the task defines group2 only by
# access method, not by permission scope (same reasoning as engine above).

resource "aws_iam_group" "group2" {
  name = "group2"
}

resource "aws_iam_user" "console_users" {
  for_each = toset(var.console_group_usernames)
  name     = each.value
}

resource "aws_iam_group_membership" "group2_members" {
  name  = "group2-membership"
  group = aws_iam_group.group2.name
  users = [for u in aws_iam_user.console_users : u.name]
}

resource "aws_iam_user_login_profile" "console_users" {
  for_each                = aws_iam_user.console_users
  user                    = each.value.name
  password_reset_required = true
}

resource "aws_iam_access_key" "console_users" {
  for_each = aws_iam_user.console_users
  user     = each.value.name
}

# ---- Account A: roleA - admin except IAM ----

data "aws_iam_policy_document" "account_a_root_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:root"]
    }
  }
}

resource "aws_iam_role" "roleA" {
  name               = "roleA"
  assume_role_policy = data.aws_iam_policy_document.account_a_root_trust.json
}

data "aws_iam_policy_document" "roleA_permissions" {
  statement {
    sid       = "AllowEverything"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyIAM"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "roleA_permissions" {
  name   = "roleA-admin-except-iam"
  role   = aws_iam_role.roleA.id
  policy = data.aws_iam_policy_document.roleA_permissions.json
}

# ---- Account A: roleB - may only assume roleC in Account B ----

resource "aws_iam_role" "roleB" {
  name               = "roleB"
  assume_role_policy = data.aws_iam_policy_document.account_a_root_trust.json
}

data "aws_iam_policy_document" "roleB_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${var.account_b_id}:role/roleC"]
  }
}

resource "aws_iam_role_policy" "roleB_permissions" {
  name   = "roleB-assume-roleC"
  role   = aws_iam_role.roleB.id
  policy = data.aws_iam_policy_document.roleB_permissions.json
}

# ---- Account B: roleC - full access to one named bucket, assumable only by roleB ----
#
# Trust policy is scoped to roleB's specific ARN, not the Account A root.
# See NOTES.md for why that distinction matters.

data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.roleB.arn]
    }
  }
}

resource "aws_iam_role" "roleC" {
  provider           = aws.account_b
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

data "aws_iam_policy_document" "roleC_permissions" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.roleC_bucket_name}",
      "arn:aws:s3:::${var.roleC_bucket_name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "roleC_permissions" {
  provider = aws.account_b
  name     = "roleC-s3-full-access"
  role     = aws_iam_role.roleC.id
  policy   = data.aws_iam_policy_document.roleC_permissions.json
}
