variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "allowed_ingress_cidrs" {
  type    = list(string)
  default = []
}
