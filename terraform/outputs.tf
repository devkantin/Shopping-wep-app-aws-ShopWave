output "app_url" {
  value       = "http://${aws_lb.main.dns_name}"
  description = "ShopWave application URL"
}

output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "rds_endpoint" {
  value     = aws_db_instance.mysql.address
  sensitive = true
}

output "app_bucket" {
  value = aws_s3_bucket.app.id
}
