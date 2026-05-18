terraform {
  # OpenTofu 1.6+ or Terraform 1.5+ both work.
  required_version = ">= 1.5.0"

  required_providers {
    terrifi = {
      source  = "alexklibisz/terrifi"
      version = "~> 0.6" # latest 0.x at time of writing (Apr 2026)
    }
  }
}
