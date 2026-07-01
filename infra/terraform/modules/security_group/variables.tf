variable "project" { type = string }
variable "vpc_id" { type = string }
variable "my_cidr" {
  description = "The /32 allowed to reach SSH and the k8s API."
  type        = string
}
