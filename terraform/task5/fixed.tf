# Task 5 - fixed version of the broken snippet. Two bugs, explained in NOTES.md:
#   1. Trust policy pointed at a non-existent IAM *user* ("user/roleB") instead
#      of the IAM *role* roleB ("role/roleB").
#   2. Permissions policy granted s3:* on Resource "*" (every bucket in the
#      account), instead of being scoped to the one named bucket the task
#      asked for.
#
# This is the same pattern already implemented for real in ../iam.tf
# (data.aws_iam_policy_document.roleC_trust / roleC_permissions), which also
# trusts roleB's specific ARN rather than this hardcoded string, and reads
# the bucket name from a variable. It's reproduced standalone here as the
# direct answer to the Task 5 exercise.

variable "account_a_id" {
  type    = string
  default = "000000000000"
}

variable "roleC_bucket_name" {
  type    = string
  default = "account-b-shared-bucket"
}

data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # Bug 1 fix: roleB is an IAM role, not an IAM user.
      identifiers = ["arn:aws:iam::${var.account_a_id}:role/roleB"]
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
      Effect = "Allow"
      Action = "s3:*"
      # Bug 2 fix: scoped to the single named bucket (and its objects),
      # not every bucket in the account.
      Resource = [
        "arn:aws:s3:::${var.roleC_bucket_name}",
        "arn:aws:s3:::${var.roleC_bucket_name}/*",
      ]
    }]
  })
}
