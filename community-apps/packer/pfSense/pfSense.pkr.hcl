# Download and uncompress the .iso.gz image
source "null" "download_iso" { communicator = "none" }

build {
  sources = ["source.null.download_iso"]

  provisioner "shell-local" {
    inline = [
      "echo Downloading ISO...",
      "curl -o ${var.input_dir}/${var.appliance_name}.iso.gz ${var.pfSense[var.version].iso_url}",
      "echo Extracting ISO...",
      "gunzip -f ${var.input_dir}/${var.appliance_name}.iso.gz",
    ]
  }
}


# Build VM image
source "qemu" "pfSense" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "${var.input_dir}/${var.appliance_name}.iso"
  iso_checksum = "none"

  headless = var.headless

  boot_wait    = "240s"
  boot_command = lookup(var.boot_cmd, var.version, [])

  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = 4096

  output_directory = var.output_dir

#   qemuargs = [
#     ["-cpu", "host"],
#     ["-serial", "stdio"],
#   ]

  #communicator = "ssh"
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
#   shutdown_command = "poweroff"
#   vm_name          = "${var.appliance_name}"
# }

# build {
#   sources = ["source.qemu.freebsd"]

#   # be carefull with shell inline provisioners, FreeBSD csh is tricky
#   provisioner "shell" {
#     execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
#     scripts         = ["${var.input_dir}/mkdir"]
#   }

#   provisioner "file" {
#     destination = "/tmp/context"
#     source      = "context-linux/out/"
#   }

#   provisioner "shell" {
#     execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
#     scripts         = ["${var.input_dir}/script.sh"]
#   }
# }