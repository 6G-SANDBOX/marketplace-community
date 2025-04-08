variable "appliance_name" {
  type    = string
  default = "service_grafana"
}

variable "input_dir" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "headless" {
  type    = bool
  default = false
}

variable "version" {
  type    = string
  default = ""
}
