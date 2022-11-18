variable "host" {
  description = "where the application is hosted"
  type        = string
}

variable "root_domain" {
  description = "root domain of the hosted zone"
  type        = string
}

variable "environment" {
  description = "the environment on which to deploy"
  type        = string
}

variable "application_directory" {
  description = "the directory in which the application can be found"
  type        = string
}

variable "application_name" {
  description = "the name of the application"
  type        = string
}
