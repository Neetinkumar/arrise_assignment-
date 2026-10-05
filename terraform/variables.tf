#######################################
# General
#######################################

variable "aws_region" {
  description = "AWS region for Account A resources (EC2 instances, IAM, roleA/roleB)."
  type        = string
  default     = "us-east-1"
}

#######################################
# Task 1 - Multi-instance EC2
#######################################

variable "protected_instance_key" {
  description = "Key (from var.instances) of the single instance protected by prevent_destroy. See NOTES.md for why db-primary was chosen."
  type        = string
  default     = "db-primary"
}

variable "instances" {
  description = "Map of instance name -> instance configuration. Drives all 5 EC2 instances from one variable instead of 5 hardcoded resource blocks."
  type = map(object({
    instance_type    = string
    ami_id           = optional(string) # if null, falls back to the latest Amazon Linux 2023 AMI
    root_volume_type = string           # gp2 | gp3 | io1 | io2
    root_volume_size = number           # GiB
    root_volume_iops = optional(number) # required for io1/io2, ignored otherwise
    key_name         = string           # must already exist in the target account/region
    environment      = string
    owner            = string
  }))

  default = {
    "web-1" = {
      instance_type    = "t3.micro"
      root_volume_type = "gp3"
      root_volume_size = 20
      key_name         = "web-1-keypair"
      environment      = "production"
      owner            = "web-team"
    }
    "web-2" = {
      instance_type    = "t3.small"
      root_volume_type = "gp3"
      root_volume_size = 20
      key_name         = "web-2-keypair"
      environment      = "production"
      owner            = "web-team"
    }
    "app-1" = {
      instance_type    = "m5.large"
      root_volume_type = "gp3"
      root_volume_size = 50
      key_name         = "app-1-keypair"
      environment      = "production"
      owner            = "app-team"
    }
    # Protected instance (see var.protected_instance_key / NOTES.md).
    # Also satisfies the "at least one io1/io2 instance" requirement.
    "db-primary" = {
      instance_type    = "r5.large"
      root_volume_type = "io2"
      root_volume_size = 100
      root_volume_iops = 3000
      key_name         = "db-primary-keypair"
      environment      = "production"
      owner            = "data-team"
    }
    "cache-1" = {
      instance_type    = "t3.medium"
      root_volume_type = "gp2"
      root_volume_size = 20
      key_name         = "cache-1-keypair"
      environment      = "staging"
      owner            = "platform-team"
    }
  }

  validation {
    condition     = length([for k, v in var.instances : k if contains(["io1", "io2"], v.root_volume_type)]) > 0
    error_message = "At least one instance in var.instances must use an io1 or io2 root volume."
  }

  validation {
    condition     = contains(keys(var.instances), var.protected_instance_key)
    error_message = "var.protected_instance_key must be a key present in var.instances."
  }
}

#######################################
# Task 3 - Multi-account IAM
#######################################

variable "account_a_id" {
  description = "Account A ID - where group1/group2, roleA, roleB, engine and ci live."
  type        = string
  default     = "000000000000"
}

variable "account_b_id" {
  description = "Account B ID - where roleC and the target S3 bucket live."
  type        = string
  default     = "111111111111"
}

variable "account_b_terraform_role_arn" {
  description = "Role Terraform assumes in Account B to provision roleC. Operator/CI-pipeline concern, separate from roleB/roleC."
  type        = string
  default     = "arn:aws:iam::111111111111:role/terraform-deploy"
}

variable "console_group_usernames" {
  description = "The two named users in group2 (full console + CLI access)."
  type        = list(string)
  default     = ["alice", "bob"]
}

variable "roleC_bucket_name" {
  description = "Name of the single S3 bucket (in Account B) that roleC gets full access to."
  type        = string
  default     = "account-b-shared-bucket"
}

#######################################
# Task 4 - least-privilege ci policy
#######################################

variable "ecr_repository_arn" {
  description = "ARN of the single ECR repository the ci user may push images to."
  type        = string
  default     = "arn:aws:ecr:us-east-1:000000000000:repository/my-app"
}

variable "ecs_service_arn" {
  description = "ARN of the single ECS service the ci user may deploy new task definitions to."
  type        = string
  default     = "arn:aws:ecs:us-east-1:000000000000:service/my-cluster/my-service"
}

variable "ecs_task_execution_role_arn" {
  description = "Task execution role the ci user is allowed to PassRole to ECS, and nowhere else."
  type        = string
  default     = "arn:aws:iam::000000000000:role/my-app-ecs-task-execution-role"
}

variable "ci_artifacts_bucket_name" {
  description = "Name of the single S3 bucket holding build artifacts, read-only for ci."
  type        = string
  default     = "my-app-build-artifacts"
}
