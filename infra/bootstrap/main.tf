terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state on purpose: applied once, holds no secrets, and the state file is gitignored.
}

variable "region" {
  type    = string
  default = "ap-southeast-2"
}
variable "profile" {
  type    = string
  default = "sentinel"
}
variable "github_repo" {
  description = "GitHub repository as owner/name allowed to assume the deploy role"
  type        = string
}

provider "aws" {
  region  = var.region
  profile = var.profile
  default_tags {
    tags = {
      Project   = "sentinel"
      Env       = "demo"
      Ephemeral = "true"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "sentinel-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = "sentinel-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

module "ecr" {
  source = "../modules/ecr"
  name   = "sentinel-app"
}

module "oidc" {
  source             = "../modules/oidc"
  name               = "sentinel"
  region             = var.region
  github_repo        = var.github_repo
  state_bucket_arn   = aws_s3_bucket.state.arn
  lock_table_arn     = aws_dynamodb_table.locks.arn
  ecr_repository_arn = module.ecr.repository_arn
}

output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "lock_table" { value = aws_dynamodb_table.locks.name }
output "ecr_repository_url" { value = module.ecr.repository_url }
output "deploy_role_arn" { value = module.oidc.deploy_role_arn }
output "plan_role_arn" { value = module.oidc.plan_role_arn }
