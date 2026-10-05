# Default provider talks to Account A (where this root module is primarily deployed).
provider "aws" {
  region = var.aws_region
}

# Account B is a separate AWS account (Task 3). Terraform needs its own credentials
# path into Account B to create roleC there. This assumes whoever runs `terraform
# apply` has a role in Account B they can assume for provisioning purposes - that
# role is unrelated to roleB/roleC, which are the application-level cross-account
# roles this module defines.
provider "aws" {
  alias  = "account_b"
  region = var.aws_region

  assume_role {
    role_arn = var.account_b_terraform_role_arn
  }
}
