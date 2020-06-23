# terraform-aws-waf

## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| aws | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| alb | ALB to be protected with WAF | `string` | n/a | yes |
| env | Environment name (production, development, staging) | `string` | n/a | yes |
| logging | This value is used to enable logging | `map(string)` | <pre>{<br>  "enabled": false,<br>  "s3_bucket_arn": "",<br>  "s3_bucket_name": ""<br>}</pre> | no |
| namespace | Name of the company | `string` | `"ontex"` | no |
| project | Project code for the resource | `string` | n/a | yes |
| region | AWS region | `string` | n/a | yes |
| tags | List of tags to apply to the resource | `any` | n/a | yes |

## Outputs

No output.

