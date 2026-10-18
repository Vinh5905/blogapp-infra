terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.56, < 7.0"
    }
  }
}

provider "aws" {
  region              = "ap-southeast-1"
  allowed_account_ids = ["947856326077"]

  default_tags {
    tags = {
      Project     = "blogapp"
      Environment = "dev"
      ManagedBy   = "terraform"
      Component   = "state-backend"
    }
  }
}