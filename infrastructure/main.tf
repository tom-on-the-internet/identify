locals {
  name_and_env = "${var.application_name}-${var.environment}"

  // the zip file name will have the date appended to it so
  // that terraform knows when it has changed
  zip_file = "${var.application_directory}/${one(fileset(var.application_directory, "${var.application_name}*.zip"))}"
}

resource "aws_s3_bucket" "this" {
  bucket = "${local.name_and_env}-lambda-bucket"
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  acl    = "private"
}

resource "aws_s3_object" "this" {
  bucket = aws_s3_bucket.this.id
  key    = "${var.application_name}.zip"
  source = local.zip_file
}

resource "aws_iam_role" "this" {
  name = "${local.name_and_env}-lambda_exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_lambda_function" "this" {
  function_name = local.name_and_env

  s3_bucket = aws_s3_bucket.this.id
  s3_key    = aws_s3_object.this.key

  runtime = "provided.al2"
  handler = var.application_name

  source_code_hash = filebase64sha256(local.zip_file)

  role   = aws_iam_role.this.arn
  layers = ["arn:aws:lambda:ca-central-1:901920570463:layer:aws-otel-collector-amd64-ver-0-62-1:1"]

  environment {
    variables = {
      ENV = var.environment
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = 30
}

data "aws_iam_policy" "lambda_xray" {
  name = "AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray_policy" {
  role       = aws_iam_role.this.name
  policy_arn = data.aws_iam_policy.lambda_xray.arn
}

resource "aws_apigatewayv2_api" "this" {
  name          = local.name_and_env
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true


  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "this" {
  api_id = aws_apigatewayv2_api.this.id

  integration_uri    = aws_lambda_function.this.arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  description        = "This is our {proxy+} integration"
}

resource "aws_apigatewayv2_route" "this" {
  api_id = aws_apigatewayv2_api.this.id

  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.this.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# route 53
resource "aws_acm_certificate" "certificate" {
  provider          = aws.us-east-1
  domain_name       = var.host
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.host}",
  ]

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "zone" {
  name         = var.root_domain
  private_zone = false
}

resource "aws_route53_record" "record" {
  for_each = {
    for dvo in aws_acm_certificate.certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}


resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.host
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "subdomain" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "*.${var.host}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# cloudfront
resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = replace(aws_apigatewayv2_stage.this.invoke_url, "/^https?://([^/]*).*/", "$1")
    origin_id   = aws_apigatewayv2_stage.this.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled = true

  aliases = [var.host, "*.${var.host}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_apigatewayv2_stage.this.id

    forwarded_values {
      query_string = true

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.this.arn
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.certificate.arn
    ssl_support_method  = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_cloudfront_function" "this" {
  name    = "${local.name_and_env}-add-x-forward-host-header"
  runtime = "cloudfront-js-1.0"
  code    = file("${path.module}/add-x-forwarded-host-header.js")

  lifecycle {
    create_before_destroy = true
  }
}
