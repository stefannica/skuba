data "template_file" "master_repositories" {
  template = "${file("cloud-init/repository.tpl")}"
  count    = "${length(var.repositories)}"

  vars {
    repository_url  = "${element(values(var.repositories[count.index]), 0)}"
    repository_name = "${element(keys(var.repositories[count.index]), 0)}"
  }
}

data "template_file" "master_registration" {
  template = "${file("cloud-init/registration.tpl")}"
  count    = "${var.caasp_registry_code == "" ? 0 : 1}"

  vars {
    caasp_registry_code = "${var.caasp_registry_code}"
    packages            = "${join(", ", var.packages)}"
  }
}

data "template_file" "master_commands" {
  template = "${file("cloud-init/commands.tpl")}"

  vars {
    packages = "${join(", ", var.packages)}"
  }
}

data "template_file" "master_cloud_init_metadata" {
  template = "${file("cloud-init/metadata.tpl")}"

  vars {
    network_config = "${base64gzip(data.local_file.network_cloud_init.content)}"
    instance_id    = "${var.stack_name}-master"
  }
}

data "template_file" "master_cloud_init_userdata" {
  template = "${file("cloud-init/common.tpl")}"

  vars {
    authorized_keys = "${join("\n", formatlist("  - %s", var.authorized_keys))}"
    repositories    = "${join("\n", data.template_file.master_repositories.*.rendered)}"
    registration    = "${join("\n", data.template_file.master_registration.*.rendered)}"
    commands        = "${join("\n", data.template_file.master_commands.*.rendered)}"
    username        = "${var.username}"
    password        = "${var.password}"
    ntp_servers     = "${join("\n", formatlist ("    - %s", var.ntp_servers))}"
  }
}

resource "vsphere_virtual_machine" "master" {
  count            = "${var.masters}"
  name             = "${var.stack_name}-master-${count.index}"
  num_cpus         = "${var.master_cpus}"
  memory           = "${var.master_memory}"
  guest_id         = "${var.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"
  }

  disk {
    label        = "disk0"
    datastore_id = "${data.vsphere_datastore.datastore.id}"
    size         = "${data.vsphere_virtual_machine.template.disks.0.size}"
  }

  extra_config {
    "guestinfo.metadata"          = "${base64gzip(data.template_file.master_cloud_init_metadata.rendered)}"
    "guestinfo.metadata.encoding" = "gzip+base64"

    "guestinfo.userdata"          = "${base64gzip(data.template_file.master_cloud_init_userdata.rendered)}"
    "guestinfo.userdata.encoding" = "gzip+base64"
  }

  network_interface {
    network_id = "${data.vsphere_network.network.id}"
  }
}

resource "null_resource" "master_wait_cloudinit" {
  count = "${var.masters}"

  connection {
    host     = "${element(vsphere_virtual_machine.master.*.guest_ip_addresses.0, count.index)}"
    user     = "${var.username}"
    password = "${var.password}"
    type     = "ssh"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
    ]
  }
}