output "alb_dns_name" {
  value       = aws_lb.web.dns_name
  description = "The DNS name of the load balancer"
}

output "database_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "The endpoint of the database"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.logs.id
  description = "The name of the S3 bucket for logs"
}