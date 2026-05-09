terraform {
  backend "s3" {
    bucket         = "ammonl-db-tf-state"
    key            = "infra-shared-db/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "ammonl-db-tf-locks"
    encrypt        = true
  }
}
