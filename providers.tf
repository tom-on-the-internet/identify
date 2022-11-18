terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.16"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.2.0"
    }
  }

  required_version = ">=1.3"
}

provider "aws" {
  region = "ca-central-1"
}
