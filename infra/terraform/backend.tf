terraform {
  backend "s3" {
    bucket         = "gbadedata-capstone-tfstate"
    key            = "capstone-phoenix/infra/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "gbadedata-capstone-tf-lock"
    encrypt        = true
  }
}
