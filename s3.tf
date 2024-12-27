resource "aws_s3_bucket" "logs" {
  bucket = "${var.environment}-app-logs-${random_string.suffix.result}"

  tags = {
    Name        = "${var.environment}-app-logs"
    Environment = var.environment
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}