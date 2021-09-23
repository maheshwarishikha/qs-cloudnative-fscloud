terraform {
  required_version = ">= 0.14.0"
  required_providers {
    ibm = {
      source  = "ibm-cloud/ibm"
      version = ">= 1.27.0"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "null" {
}

resource "ibm_is_vpc" "vpc1" {
  name  = "bank-vpc-${formatdate("YYYYMMDDhhmm", timestamp())}"
}

resource "ibm_is_public_gateway" "vpc_gateway" {
  name = "vpc-gateway-${formatdate("YYYYMMDDhhmm", timestamp())}"
  vpc  = ibm_is_vpc.vpc1.id
  zone = var.datacenter
}

resource "ibm_is_subnet" "subnet1" {
  name                     = "bank-subnet-${formatdate("YYYYMMDDhhmm", timestamp())}"
  vpc                      = ibm_is_vpc.vpc1.id
  zone                     = var.datacenter
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.vpc_gateway.id
}

resource "ibm_resource_instance" "cos_instance" {
  name     = "bank-cos-instance-${formatdate("YYYYMMDDhhmm", timestamp())}"
  service  = "cloud-object-storage"
  plan     = "standard"
  location = "global"
}

data "ibm_resource_group" "resource_group" {
  name = var.resource_group
}

resource "ibm_container_vpc_cluster" "cluster" {
  name              = "bank_vpc_cluster-${formatdate("YYYYMMDDhhmm", timestamp())}"
  vpc_id            = ibm_is_vpc.vpc1.id
  kube_version      = var.kube_version
  flavor            = var.machine_type
  worker_count      = var.default_pool_size
  cos_instance_crn  = ibm_resource_instance.cos_instance.id
  resource_group_id = data.ibm_resource_group.resource_group.id
  zones {
      subnet_id = ibm_is_subnet.subnet1.id
      name      = var.datacenter
    }
}

resource "null_resource" "create_kubernetes_toolchain" {
  depends_on = [ibm_container_vpc_cluster.cluster]
  provisioner "local-exec" {
    command = "${path.cwd}/scripts/create-toolchain.sh"
    environment = {
      MOBILE_SIM              = "mobile-simulator-${formatdate("YYYYMMDDhhmm", timestamp())}"
      REGION                  = var.region
      TOOLCHAIN_TEMPLATE_REPO = "https://github.com/open-toolchain/simple-helm-toolchain"
      APPLICATION_REPO        = "https://github.com/IBM/example-bank"
      RESOURCE_GROUP          = var.resource_group
      API_KEY                 = var.ibmcloud_api_key
      CLUSTER_NAME            = ibm_container_vpc_cluster.cluster.name
      CLUSTER_NAMESPACE       = "example-bank"
      CONTAINER_REGISTRY_NAMESPACE = var.registry_namespace
      TOOLCHAIN_NAME          = "example-bank-toolchain-${formatdate("YYYYMMDDhhmm", timestamp())}"
      PIPELINE_TYPE           = "tekton"
      BRANCH                  = "main"
    }
  }
}
