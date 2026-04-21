resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id
  tags       = merge(local.tags, { Name = "${local.name}-db-subnet-group" })
}

resource "aws_db_instance" "mysql" {
  identifier        = "${local.name}-db"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Two private subnets across 2 AZs satisfies multi-AZ subnet requirement
  multi_az            = false # set true for production HA
  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.tags, { Name = "${local.name}-db" })
}
