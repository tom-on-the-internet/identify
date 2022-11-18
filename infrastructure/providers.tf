terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.16"
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

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}
