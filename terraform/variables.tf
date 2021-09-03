variable "toolchain_name" {
  type        = string
  description = "Name of the Compliance CI toolchain."
  default     = "example-bank-toolchain"
}

variable "region" {
  type        = string
  description = "IBM Cloud region where your application will be deployed (to view your current targeted region `ibmcloud cr region`)"
  default     = "us-south"
}

variable "registry_namespace" {
  type        = string
  description = "Container registry namespace to save images (`ibmcloud cr namespaces`). NOTE: The namespace must already exist, or be a unique value."
}

variable "resource_group" {
  type        = string
  description = "Resource group where the resources will be created (`ibmcloud resource groups`)"
  default     = "default"
}

variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster where your application is deployed. If you use the default value, a new cluster is provisioned. If you override the default value with a different cluster name, that cluster must already exist."
  default     = "bank_vpc_cluster"
}

variable "cluster_namespace" {
  type        = string
  description = "Kubernetes namespace to deploy into. NOTE: If the namespace does not exist, it will be created."
}

variable "default_pool_size" {
  default     = "3"
  description = "Number of worker nodes for the new Kubernetes cluster"
}

variable "machine_type" {
  default     = "b3c.4x16"
  description = "Name of machine type from `ibmcloud ks flavors --zone <ZONE>`"
}

variable "kube_version" {
  default     = "4.6.34_openshift"
  description = "Version of Kubernetes to apply to the new Kubernetes cluster (Run: `ibmcloud ks versions` to see available versions)"
}

variable "branch" {
  type        = string
  description = "Branch for Compliance CI toolchain template repo"
  default     = "master"
}

variable "ibmcloud_api_key" {
  type        = string
  description = "The IAM API Key for IBM Cloud access (https://cloud.ibm.com/iam/apikeys)"
}

variable "toolchain_template_repo" {
  type        = string
  description = "URL for the Toolchain Template"
  default     = "https://github.com/open-toolchain/secure-kube-toolchain"
}

variable "application_repo" {
  type        = string
  description = "URL for the application to deploy"
  default     = "https://github.com/IBM/example-bank"
}
