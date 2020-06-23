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

resource "aws_wafv2_regex_pattern_set" "regex" {
  name        = "${var.project}-${var.env}-regex-pattern"
  description = "Regex pattern"
  scope       = "REGIONAL"

  regular_expression {
    regex_string = "mag|guide-de-la-couche|media|static|admin_t0bdll|apis|locker"
  }

  tags = var.tags
}

resource "aws_wafv2_ip_set" "ip" {
  name               = "${var.project}-${var.env}-ip-set-whitelist"
  description        = "Whitelist IP set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = ["185.170.45.38/32"]

  tags = var.tags
}


resource "aws_wafv2_web_acl" "waf" {
  name        = "${var.project}-${var.env}-waf-web-acl"
  description = "Waf ACL"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "${var.project}-${var.env}-rule-rate-base-ban"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"

        scope_down_statement {
          not_statement  {
            statement {
              regex_pattern_set_reference_statement {
                arn = aws_wafv2_regex_pattern_set.regex.arn
                text_transformation {
                  priority = 0
                  type = "NONE"
                }
                field_to_match {
                  uri_path {}
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.env}-rule-rate-base-ban"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${var.project}-${var.env}-rule-ip-whitelist"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.ip.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.env}-rule-ip-whitelist"
      sampled_requests_enabled   = true
    }
  }


  rule {
    name     = "${var.project}-${var.env}-rule-timeOne-allow"
    priority = 2

    action {
      allow {}
    }

    statement {
      byte_match_statement  {
        field_to_match {
          query_string {}
        }
        positional_constraint = "CONTAINS"
        search_string = "utm_source=TimeOne"
        text_transformation {
          priority = 0
          type = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.env}-timeOne-allow"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        excluded_rule {
          name = "SizeRestrictions_QUERYSTRING"
        }
        excluded_rule {
          name = "SizeRestrictions_BODY"
        }
        excluded_rule {
          name = "SizeRestrictions_URIPATH"
        }
        excluded_rule {
          name = "GenericRFI_QUERYARGUMENTS"
        }
        excluded_rule {
          name = "GenericRFI_BODY"
        }
        excluded_rule {
          name = "CrossSiteScripting_BODY"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAnonymousIpList"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"

        excluded_rule {
          name = "HostingProviderIPList"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAnonymousIpList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 6

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesPHPRuleSet"
    priority = 7

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesPHPRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesPHPRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesLinuxRuleSet"
    priority = 8

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesLinuxRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesWordPressRuleSet"
    priority = 9

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesWordPressRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesWordPressRuleSet"
      sampled_requests_enabled   = true
    }
  }


  tags = var.tags

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.env}-waf-web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "waf_association" {
  resource_arn = var.alb
  web_acl_arn  = aws_wafv2_web_acl.waf.arn
}