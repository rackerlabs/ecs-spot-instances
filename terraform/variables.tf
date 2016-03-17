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

variable "min_instances" {
  type = "string"
  default = "2"
}

variable "max_instances" {
  type = "string"
  default = "4"
}

variable "image_id" {
  type = "string"
  default = "ami-33b48a59"
}

variable "instance_type" {
  type = "string"
  default = "m3.medium"
}

variable "bid_price" {
  type = "string"
}
