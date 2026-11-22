terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # The bucket is passed at init time so no account id is committed:
  #   terraform init -backend-config="bucket=sentinel-tfstate-<account-id>"
  # The profile comes from AWS_PROFILE locally and from OIDC credentials in CI.
  backend "s3" {
    key            = "demo/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "sentinel-tf-locks"
    encrypt        = true
  }
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}
variable "image_tag" {
  type    = string
  default = "latest"
}
variable "ecr_repository_name" {
  type    = string
  default = "sentinel-app"
}
variable "ecr_repository_url" {
  description = "Override the ECR repository URL (used for plan-only runs before bootstrap exists)"
  type        = string
  default     = ""
}
variable "alert_email" {
  type    = string
  default = ""
}
variable "task_cpu" {
  type    = number
  default = 512
}
variable "task_memory" {
  type    = number
  default = 1024
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

# Credentials: AWS_PROFILE=sentinel locally, OIDC environment credentials in GitHub Actions.
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "sentinel"
      Env       = "demo"
      Ephemeral = "true"
      Stack     = "demo"
    }
  }
}

locals {
  name       = "sentinel"
  queue_name = "sentinel-alerts"
}

data "aws_ecr_repository" "app" {
  count = var.ecr_repository_url == "" ? 1 : 0
  name  = var.ecr_repository_name
}

locals {
  ecr_url = var.ecr_repository_url != "" ? var.ecr_repository_url : data.aws_ecr_repository.app[0].repository_url
}

module "network" {
  source = "../modules/network"
  name   = local.name
}

# --- secrets (never plain env vars) ---
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "api_key" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.name}/db-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_secretsmanager_secret" "api_key" {
  name                    = "${local.name}/api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "api_key" {
  secret_id     = aws_secretsmanager_secret.api_key.id
  secret_string = random_password.api_key.result
}

module "sqs" {
  source     = "../modules/sqs"
  queue_name = local.queue_name
}

module "rds" {
  source                    = "../modules/rds"
  name                      = local.name
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.public_subnet_ids
  allowed_security_group_id = module.ecs_service.ecs_security_group_id
  instance_class            = var.db_instance_class
  password                  = random_password.db.result
}

data "aws_iam_policy_document" "task" {
  statement {
    actions = [
      "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
      "sqs:GetQueueUrl", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility",
    ]
    resources = [module.sqs.queue_arn]
  }
}

module "ecs_service" {
  source           = "../modules/ecs_service"
  name             = local.name
  region           = var.region
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.public_subnet_ids
  image            = "${local.ecr_url}:${var.image_tag}"
  cpu              = var.task_cpu
  memory           = var.task_memory
  task_policy_json = data.aws_iam_policy_document.task.json

  environment = {
    SPRING_DATASOURCE_URL             = "jdbc:postgresql://${module.rds.address}:${module.rds.port}/${module.rds.db_name}"
    SPRING_DATASOURCE_USERNAME        = module.rds.username
    SENTINEL_QUEUE_NAME               = local.queue_name
    AWS_REGION                        = var.region
    LOGGING_STRUCTURED_FORMAT_CONSOLE = "logstash"
  }
  secrets = {
    SPRING_DATASOURCE_PASSWORD = aws_secretsmanager_secret.db_password.arn
    SENTINEL_API_KEY           = aws_secretsmanager_secret.api_key.arn
  }

  depends_on = [aws_secretsmanager_secret_version.db_password, aws_secretsmanager_secret_version.api_key]
}

module "monitoring" {
  source         = "../modules/monitoring"
  name           = local.name
  region         = var.region
  alb_arn_suffix = module.ecs_service.alb_arn_suffix
  cluster_name   = module.ecs_service.cluster_name
  service_name   = module.ecs_service.service_name
  queue_name     = module.sqs.queue_name
  dlq_name       = module.sqs.dlq_name
  db_identifier  = module.rds.identifier
  alert_email    = var.alert_email
}

output "alb_dns_name" { value = module.ecs_service.alb_dns_name }
output "queue_url" { value = module.sqs.queue_url }
output "api_key_secret_arn" { value = aws_secretsmanager_secret.api_key.arn }
output "dashboard_name" { value = module.monitoring.dashboard_name }
