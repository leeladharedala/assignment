provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "mock_energy_data" {
  bucket = "mock-energy-data"
}

resource "aws_s3_bucket" "glue_script_bucket" {
  bucket = "energy-glue-script"
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_script_bucket.id
  key    = "data_generator.py"
  source = "../src/glue/data_generator.py"
  etag   = filemd5("../src/glue/data_generator.py")
}

resource "aws_s3_object" "glue_dependencies" {
  bucket = aws_s3_bucket.glue_script_bucket.id
  key    = "Faker-36.1.0-py3-none-any.whl"
  source = "../dependencies/Faker-36.1.0-py3-none-any.whl"
  etag   = filemd5("../dependencies/Faker-36.1.0-py3-none-any.whl")
}

resource "aws_glue_job" "generate_data_job" {
  name     = "generate_data-job"
  role_arn = aws_iam_role.glue_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_script_bucket.bucket}/data_generator.py"
    python_version  = "3"
  }

  default_arguments = {
    "--TempDir"                     = "s3://${aws_s3_bucket.mock_energy_data.bucket}/temp/"
    "--extra-py-files"              = "s3://${aws_s3_bucket.glue_script_bucket.bucket}/${aws_s3_object.glue_dependencies.key}"
    "--additional-python-modules"   = "faker==24.8.0,pytz==2024.1"
  }

  glue_version = "4.0"
  number_of_workers = 5
  worker_type = "G.1X"
  depends_on = [
    aws_iam_role_policy_attachment.glue_s3_policy,
    aws_iam_role_policy_attachment.glue_s3_access,
    aws_s3_object.glue_script,
    aws_s3_object.glue_dependencies
  ]
}

resource "aws_iam_role" "glue_role" {
  name = "glue-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "glue.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_policy" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_s3_access" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "glue_dynamodb_access" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "glue_notebook_sagemaker_policy" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_glue_trigger" "five_min_trigger" {
  name          = "five-minute-trigger"
  type          = "SCHEDULED"
  schedule      = "cron(0/5 * * * ? *)"
  enabled       = true
  actions {
    job_name = aws_glue_job.generate_data_job.name
  }
}

resource "aws_dynamodb_table" "energy_site_data" {
  name         = "EnergySiteData"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "site_id"
  range_key = "timestamp"

  attribute {
    name = "site_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}
#
resource "aws_iam_role" "lambda_role" {
  name = "lambda_s3_dynamodb_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_sns_topic" "energy_anomaly_alerts" {
  name = "EnergyAnomalyAlerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.energy_anomaly_alerts.arn
  protocol  = "email"
  endpoint  = "leeladharedala@gmail.com"
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_s3_dynamodb_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:*"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject"
        ],
        Resource = "${aws_s3_bucket.mock_energy_data.arn}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = "${aws_s3_bucket.mock_energy_data.arn}"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        Resource = aws_dynamodb_table.energy_site_data.arn
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = aws_sns_topic.energy_anomaly_alerts.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}
#
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../src/lambda_function"
  output_path = "../out/lambda_function.zip"
}
#
resource "aws_lambda_function" "process_energy_data" {
  function_name = "process_energy_data_lambda"
  filename      = data.archive_file.lambda_zip.output_path
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"

  role          = aws_iam_role.lambda_role.arn

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256


  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.energy_site_data.name
      SNS_TOPIC_ARN  = aws_sns_topic.energy_anomaly_alerts.arn
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.mock_energy_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_energy_data.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "rawdata/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_energy_data.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.mock_energy_data.arn
}

resource "aws_lambda_layer_version" "fastapi_layer" {
  filename   = "../dependencies/layer3.zip"
  layer_name = "fastapi-layer"
  compatible_runtimes = ["python3.9"]
}

data "archive_file" "function1" {
  type        = "zip"
  source_file  = "../src/api/function1.py"
  output_path = "../out/function1.zip"
}
#
resource "aws_lambda_function" "function1" {
  function_name = "function1"
  filename      = data.archive_file.function1.output_path
  handler       = "function1.handler"
  runtime       = "python3.9"

  role          = aws_iam_role.lambda_role.arn
  layers        = [aws_lambda_layer_version.fastapi_layer.arn]

  source_code_hash = data.archive_file.function1.output_base64sha256


  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.energy_site_data.name
    }
  }
}

data "archive_file" "function2" {
  type        = "zip"
  source_file  = "../src/api/function2.py"
  output_path = "../out/function2.zip"
}

resource "aws_lambda_function" "function2" {
  function_name = "function2"
  filename      = data.archive_file.function2.output_path
  handler       = "function2.handler"
  runtime       = "python3.9"

  role          = aws_iam_role.lambda_role.arn
  layers        = [aws_lambda_layer_version.fastapi_layer.arn]

  source_code_hash = data.archive_file.function2.output_base64sha256


  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.energy_site_data.name
    }
  }
}

data "archive_file" "function3" {
  type        = "zip"
  source_file  = "../src/api/function3.py"
  output_path = "../out/function3.zip"
}

resource "aws_lambda_function" "function3" {
  function_name = "function3"
  filename      = data.archive_file.function3.output_path
  handler       = "function3.handler"
  runtime       = "python3.9"

  role          = aws_iam_role.lambda_role.arn
  layers        = [aws_lambda_layer_version.fastapi_layer.arn]

  source_code_hash = data.archive_file.function3.output_base64sha256


  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.energy_site_data.name
    }
  }
}

resource "aws_apigatewayv2_api" "energy_api" {
  name          = "energy-api"
  protocol_type = "HTTP"
  description   = "API for energy data"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.energy_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "records_integration" {
  api_id                 = aws_apigatewayv2_api.energy_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.function1.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_records" {
  api_id    = aws_apigatewayv2_api.energy_api.id
  route_key = "GET /records/{site_id}"

  target = "integrations/${aws_apigatewayv2_integration.records_integration.id}"
}

resource "aws_apigatewayv2_integration" "anomalies_integration" {
  api_id                 = aws_apigatewayv2_api.energy_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.function2.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_anomalies" {
  api_id    = aws_apigatewayv2_api.energy_api.id
  route_key = "GET /anomalies/{site_id}"

  target = "integrations/${aws_apigatewayv2_integration.anomalies_integration.id}"
}

resource "aws_apigatewayv2_integration" "negative_energy_integration" {
  api_id                 = aws_apigatewayv2_api.energy_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.function3.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_negative_energy" {
  api_id    = aws_apigatewayv2_api.energy_api.id
  route_key = "GET /net_negative_energy"

  target = "integrations/${aws_apigatewayv2_integration.negative_energy_integration.id}"
}

resource "aws_lambda_permission" "allow_function1" {
  statement_id  = "AllowFunction1Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function1.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.energy_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_function2" {
  statement_id  = "AllowFunction2Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function2.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.energy_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_function3" {
  statement_id  = "AllowFunction3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function3.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.energy_api.execution_arn}/*/*"
}

output "base_url" {
  value = "${aws_apigatewayv2_api.energy_api.api_endpoint}/"
}

output "records_url" {
  value = "${aws_apigatewayv2_api.energy_api.api_endpoint}/records"
}

output "anomalies_url" {
  value = "${aws_apigatewayv2_api.energy_api.api_endpoint}/anomalies"
}

output "negative_energy_url" {
  value = "${aws_apigatewayv2_api.energy_api.api_endpoint}/net_negative_energy"
}