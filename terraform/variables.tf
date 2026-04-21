variable "region"           { default = "us-east-1" }
variable "project"          { default = "shopwave" }
variable "environment"      { default = "prod" }
variable "db_name"          { default = "shopwave_db" }
variable "db_username"      { default = "admin" }
variable "db_password"      { type = string; sensitive = true }
variable "instance_type"    { default = "t3.micro" }
variable "db_instance_class"{ default = "db.t3.micro" }
variable "asg_min"          { default = 1 }
variable "asg_max"          { default = 4 }
variable "asg_desired"      { default = 2 }
