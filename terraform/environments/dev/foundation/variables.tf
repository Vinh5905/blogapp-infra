variable "aws_account_id" {
  description = "AWS account allowed to host BlogApp dev."
  type        = string
  default     = "947856326077"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain exactly 12 digits."
  }
}

variable "aws_region" {
  description = "AWS Region for BlogApp dev."
  type        = string
  default     = "ap-southeast-1"
}

variable "availability_zones" {
  description = "Two available standard AZ names, in stable subnet order."
  type        = list(string)

  validation {
    condition = (
      length(var.availability_zones) == 2 &&
      length(distinct(var.availability_zones)) == 2
    )
    error_message = "Choose exactly two distinct Availability Zones."
  }
}

variable "api_allowed_ipv4_cidrs" {
  description = "Optional approved VPN IPv4 CIDRs for API NLB port 6443; requires a working route to the NLB."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.api_allowed_ipv4_cidrs : try(
        cidrnetmask(cidr) != "" && tonumber(split("/", cidr)[1]) > 0,
        false
      )
    ])
    error_message = "Use valid, restricted IPv4 CIDRs; 0.0.0.0/0 and IPv6 are not allowed for the API."
  }
}
