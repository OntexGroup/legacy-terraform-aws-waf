include {
  path = "${find_in_parent_folders()}"
}

# AWS Waf needs on ALB or cloudfront distribution.
dependency "ec2" {
  config_path = "../ec2-asg-lbc-pprod"
}

# If you enable logs, you need to create a bucket.
dependency "s3" {
  config_path = "../s3-bucket-waf-logs"
}

terraform {
  source = "git::git@github.com:OntexGroup/terraform-aws-waf.git?ref=v3.0.3"
}

locals {
  aws_region               = basename(dirname(get_terragrunt_dir()))
  project                  = "my_project"
  env                      = "dev"
  custom_tags              = yamldecode(file("${find_in_parent_folders("custom_tags.yaml")}"))
}


inputs = {
  region                  = local.aws_region
  project                 = local.project
  tags                    = local.custom_tags
  env                     = local.env
  alb                     = dependency.ec2.outputs.alb_arn_full
  logging                 = {
    enabled = true
    s3_bucket_name = dependency.s3.outputs.this_s3_bucket_id
    s3_bucket_arn  = dependency.s3.outputs.this_s3_bucket_arn 
  }
}
