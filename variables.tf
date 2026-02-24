variable "ecr_repository_url" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type    = string
  default = "strapi"
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type = string
}