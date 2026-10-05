# Task 2 - Remote state & locking.
#
# Backend blocks cannot reference variables or locals - the values must be
# literal, because Terraform needs them before it has evaluated anything else.
# Replace the placeholders below with the real bucket/table names output by
# ./bootstrap (bootstrap/outputs.tf), then run `terraform init -migrate-state`.
#
# See NOTES.md for what happens today with local state if two people run
# `apply` at the same time, and how this backend prevents it.

terraform {
  backend "s3" {
    bucket         = "REPLACE_ME-tfstate-bucket"
    key            = "devops-assignment/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_ME-tf-locks"
    encrypt        = true
  }
}
