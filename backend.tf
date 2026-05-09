terraform {
  backend "s3" {
    bucket         = "REPLACE_ME_STATE_BUCKET"
    key            = "infra-shared-db/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "REPLACE_ME_LOCK_TABLE"
    encrypt        = true
  }
}
