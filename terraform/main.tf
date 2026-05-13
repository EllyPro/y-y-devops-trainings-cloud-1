terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {

  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "foo" {}

resource "yandex_vpc_subnet" "foo" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

locals {
  folder_id = "b1gvtik77vkkkeso2ga7"
  service-accounts = toset([
    "catgpt-sa",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "container-registry.images.pusher",
    "monitoring.editor",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${local.folder_id}-${each.key}"
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}
resource "yandex_compute_instance" "catgpt" {
    name               = "catgpt-${count.index}"
    count              = 2
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      subnet_id = "${yandex_vpc_subnet.foo.id}"
      nat = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = file("${path.module}/docker-compose.yaml")
        user-data = <<-EOT
        #cloud-config
        write_files:
          - path: /etc/unified-agent/config.yml
            permissions: '0644'
            content: |
        ${indent(6, file("${path.module}/unified-agent.yml"))}
        EOT
      ssh-keys  = "ubuntu:${file("~/.ssh/devops_training.pub")}"
    }
}

resource "yandex_lb_target_group" "catgpt-tg" {
  name = "catgpt-tg"
  description = "Target group for CatGPT instances"
  dynamic "target" {
    for_each = yandex_compute_instance.catgpt
    content {
      subnet_id = yandex_vpc_subnet.foo.id
      address   = target.value.network_interface[0].ip_address
    }
    
  }
}

resource "yandex_lb_network_load_balancer" "catgpt-lb" {
  name = "catgpt-lb"

  listener {
    name = "http"

    port = 8080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.catgpt-tg.id

    healthcheck {
      name = "http-health"

      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}


