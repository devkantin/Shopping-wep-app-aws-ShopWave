variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "shopwave"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "db_name" {
  type    = string
  default = "shopwave_db"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "asg_min" {
  type    = number
  default = 1
}

variable "asg_max" {
  type    = number
  default = 4
}

variable "asg_desired" {
  type    = number
  default = 2
}
