packer {
  required_plugins {
    docker = {
      version = ">= 0.0.7"
      source  = "github.com/hashicorp/docker"
    }
  }
}

source "docker" "percona-postgres-server" {
  image  = "ubuntu:jammy"  # Adjust the base image according to your requirements
  commit = true
  volumes = {
    "/var/run/docker.sock" = "/var/run/docker.sock"
  }
}
variable "docker_username" {
  type    = string
  default = ""
}
variable "docker_password" {
  type    = string
  default = ""
}
variable "tag" {
  type    = string
  default = ""
}
variable "git_token" {
  type    = string
  default = ""
}
variable "postgres_version" {
  type    = string
  default = ""
}
variable "gopath" {
  type    = string
  default = ""
}
variable "branch" {
  type    = string
  default = ""
}
build {
  name = "Percona-postgres-server-Image"
  sources = [
    "source.docker.percona-postgres-server"
  ]
  provisioner "shell" {
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y make curl wget jq ca-certificates git gnupg lsb-release sudo software-properties-common",
      "sudo apt-get install -y docker.io",
      "sudo apt install docker-buildx",
      "wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz",
      "sudo tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz",
      "export PATH=$PATH:/usr/local/go/bin",
      "go version",
      "export GOPATH=~/go",
      "mkdir -p ${var.gopath}/src/github.com/zalando/",
      "cd ${var.gopath}/src/github.com/zalando/",
      "git clone https://avnshrai:${var.git_token}@github.com/coredgeio/postgres-operator.git",
      "cd postgres-operator && git checkout tags/${var.branch}",
      "make deps",
      "export TAG=${var.tag}",
      "export IMAGE=coredgeio/postgres-operator",
      "make docker",
      "docker tag coredgeio/postgres-operator:${var.tag} coredgeio/postgres-operator:latest",
      "docker login -u ${var.docker_username} -p ${var.docker_password}",
      "docker push coredgeio/postgres-operator:${var.tag}",
      "docker push coredgeio/postgres-operator:latest",
    ]
  }

  post-processor "docker-tag" {
    repository = "coredegeio/postgres-operator"  # Adjust repository name as needed
    tags       = ["latest"]
  }
}