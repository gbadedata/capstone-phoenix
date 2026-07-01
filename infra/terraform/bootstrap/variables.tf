variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket for remote state. Must match backend.tf in the parent config."
  type        = string
  default     = "gbadedata-capstone-tfstate"
}

variable "lock_table_name" {
  description = "DynamoDB table for state locking. Must match backend.tf in the parent config."
  type        = string
  default     = "gbadedata-capstone-tf-lock"
}
