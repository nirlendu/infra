variable "region" {
  type        = string
  default     = "us-east-1"
  description = "The estate is us-east-1. ap-south-1 holds buckets and nothing that runs."
}

variable "env" {
  type        = string
  default     = "prod"
  description = "Names the clusters and the SSM prefix they publish to."
}

variable "shared_env" {
  type        = string
  default     = "prod"
  description = "Which shared VPC to attach the service-discovery namespaces to."
}

variable "companies" {
  type = map(object({
    # A cluster is created only for companies that actually run something. Adding a
    # name here with no product is free but noisy — an empty cluster in the console
    # reads as "something failed" rather than "nothing built yet".
    description = string

    # Fargate Spot is ~70% cheaper and interrupts with a two-minute warning. It is
    # the right default for a company whose products have few users; flip it per
    # company once someone would notice a one-minute gap.
    prefer_spot = optional(bool, true)

    log_retention_days = optional(number, 7)
  }))

  description = "Companies that get a cluster. The key is the company name and becomes `<company>-<env>`."

  default = {
    geniusjnr = {
      description = "geniusjnr — uni-backend first, more to follow."
      prefer_spot = true
    }
  }
}
