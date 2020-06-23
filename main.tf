data "aws_caller_identity" "current" {}

resource "aws_kinesis_firehose_delivery_stream" "kinesis_firehose_delivery_stream" {
  count       = var.logging["enabled"] ? 1 : 0
  name        = "aws-waf-logs-${var.project}-${var.env}"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.iam_role[0].arn
    bucket_arn = var.logging["s3_bucket_arn"]
  }

  tags = merge(
    var.tags,
    {
      Project = var.project
    }
  )
}

resource "aws_iam_role" "iam_role" {
  count = var.logging["enabled"] ? 1 : 0
  name  = "firehose-waf-${var.project}-${var.env}"
  tags  = var.tags

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "iam_role_policy" {
  count = var.logging["enabled"] ? 1 : 0
  name  = "firehose-waf-${var.project}-${var.env}"
  role  = aws_iam_role.iam_role[0].id

  policy = <<-EOF
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "",
              "Effect": "Allow",
              "Action": [
                  "glue:GetTable",
                  "glue:GetTableVersion",
                  "glue:GetTableVersions"
              ],
              "Resource": "*"
          },
          {
              "Sid": "",
              "Effect": "Allow",
              "Action": [
                  "s3:AbortMultipartUpload",
                  "s3:GetBucketLocation",
                  "s3:GetObject",
                  "s3:ListBucket",
                  "s3:ListBucketMultipartUploads",
                  "s3:PutObject"
              ],
              "Resource": [
                  "${var.logging["s3_bucket_arn"]}",
                  "${var.logging["s3_bucket_arn"]}/*",
                  "arn:aws:s3:::%FIREHOSE_BUCKET_NAME%",
                  "arn:aws:s3:::%FIREHOSE_BUCKET_NAME%/*"
              ]
          },
          {
              "Sid": "",
              "Effect": "Allow",
              "Action": [
                  "lambda:InvokeFunction",
                  "lambda:GetFunctionConfiguration"
              ],
              "Resource": "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:%FIREHOSE_DEFAULT_FUNCTION%:%FIREHOSE_DEFAULT_VERSION%"
          },
          {
              "Sid": "",
              "Effect": "Allow",
              "Action": [
                  "logs:PutLogEvents"
              ],
              "Resource": [
                  "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/aws-waf-logs-${var.env}-${var.project}:log-stream:*"
              ]
          },
          {
              "Sid": "",
              "Effect": "Allow",
              "Action": [
                  "kinesis:DescribeStream",
                  "kinesis:GetShardIterator",
                  "kinesis:GetRecords",
                  "kinesis:ListShards"
              ],
              "Resource": "arn:aws:kinesis:${var.region}:${data.aws_caller_identity.current.account_id}:stream/%FIREHOSE_STREAM_NAME%"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "kms:Decrypt"
              ],
              "Resource": [
                  "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/%SSE_KEY_ID%"
              ],
              "Condition": {
                  "StringEquals": {
                      "kms:ViaService": "kinesis.%REGION_NAME%.amazonaws.com"
                  },
                  "StringLike": {
                      "kms:EncryptionContext:aws:kinesis:arn": "arn:aws:kinesis:%REGION_NAME%:${data.aws_caller_identity.current.account_id}:stream/%FIREHOSE_STREAM_NAME%"
                  }
              }
          }
      ]
  }
  EOF
}

resource "aws_cloudformation_stack" "waf" {
  name = "waf-stack"
  parameters = {
    ProjectName = var.project,
    EnvName     = var.env
    WAFName     = "${var.project}-${var.env}-waf-web-acl"
    ALBARN      = var.alb
  }

  template_body = file("${path.module}/cloudformation.yaml")
}