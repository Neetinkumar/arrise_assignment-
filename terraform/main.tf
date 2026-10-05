# Task 1 - Multi-instance EC2 provisioning
#
# All 5 instances are driven by the single var.instances map. One specific
# instance (var.protected_instance_key, "db-primary" by default) is split out
# into its own for_each resource so it alone can carry `prevent_destroy = true`
# - that argument must be a literal, so it cannot vary per-key inside a single
# for_each block. This is 2 resource blocks total, not 5 hardcoded ones.
# See NOTES.md for why db-primary was chosen.

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  protected_instances   = { for name, cfg in var.instances : name => cfg if name == var.protected_instance_key }
  unprotected_instances = { for name, cfg in var.instances : name => cfg if name != var.protected_instance_key }
}

resource "aws_instance" "protected" {
  for_each = local.protected_instances

  ami           = coalesce(each.value.ami_id, data.aws_ami.amazon_linux.id)
  instance_type = each.value.instance_type
  key_name      = each.value.key_name

  root_block_device {
    volume_type = each.value.root_volume_type
    volume_size = each.value.root_volume_size
    iops        = contains(["io1", "io2"], each.value.root_volume_type) ? each.value.root_volume_iops : null
  }

  tags = {
    Name        = each.key
    Environment = each.value.environment
    Owner       = each.value.owner
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "this" {
  for_each = local.unprotected_instances

  ami           = coalesce(each.value.ami_id, data.aws_ami.amazon_linux.id)
  instance_type = each.value.instance_type
  key_name      = each.value.key_name

  root_block_device {
    volume_type = each.value.root_volume_type
    volume_size = each.value.root_volume_size
    iops        = contains(["io1", "io2"], each.value.root_volume_type) ? each.value.root_volume_iops : null
  }

  tags = {
    Name        = each.key
    Environment = each.value.environment
    Owner       = each.value.owner
  }
}
