variable "region" {
  type = "string"
}

variable "availability_zone" {
  type = "string"
}

variable "cidr_block" {
  type = "string"
  default = "10.0.0.0/16"
}
