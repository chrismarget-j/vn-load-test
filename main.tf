terraform {
  required_providers {
    apstra = {
      source = "Juniper/apstra"
    }
  }
}

provider "apstra" {
  tls_validation_disabled = true
  blueprint_mutex_enabled = false
  # DO NOT USE URL - the shell script needs env variables
  #  url                     = "https://admin:Juniper!123@172.25.90.163"
  # use environment variables instead:
  # - APSTRA_USER
  # - APSTRA_PASS
  # - APSTRA_URL
  experimental = true
  api_timeout  = 0
}

resource "apstra_datacenter_blueprint" "a" {
  name        = "chris"
  template_id = "L2_ESI_Access"
}

output "blueprint_id" { value = apstra_datacenter_blueprint.a.id }

resource "apstra_datacenter_routing_zone" "a" {
  blueprint_id = apstra_datacenter_blueprint.a.id
  name         = "chris"
}

data "apstra_datacenter_systems" "leaf_switches" {
  blueprint_id = apstra_datacenter_blueprint.a.id
  filters      = [{ role = "leaf" }]
}

data "apstra_datacenter_virtual_network_binding_constructor" "leaf_switches" {
  blueprint_id = apstra_datacenter_blueprint.a.id
  switch_ids   = [sort(tolist(data.apstra_datacenter_systems.leaf_switches.ids))[0]]
}

locals {
  block   = "10.0.0.0/8"
  leaf_id = one([for k, v in data.apstra_datacenter_virtual_network_binding_constructor.leaf_switches.bindings : k])
}

variable "vn_count" {
  type    = number
  default = 0
}

resource "apstra_datacenter_virtual_network" "vns" {
  count                     = var.vn_count
  blueprint_id              = apstra_datacenter_blueprint.a.id
  routing_zone_id           = apstra_datacenter_routing_zone.a.id
  name                      = "vn_${count.index + 3}"
  type                      = "vxlan"
  bindings                  = { (local.leaf_id) = { vlan_id = count.index + 3 } }
  ipv4_connectivity_enabled = true
  ipv4_subnet               = cidrsubnet(local.block, 16, count.index + 3)
}
