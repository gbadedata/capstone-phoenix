terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# NOTE: bootstrap intentionally uses LOCAL state (no backend block). It creates the very
# bucket/table the main config uses for remote state — it cannot store its own state there.
# Its local terraform.tfstate is gitignored.
