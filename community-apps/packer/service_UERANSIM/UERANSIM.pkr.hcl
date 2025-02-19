source "null" "null" { communicator = "none" }

build {
  sources = ["source.null.null"]

  # TODO: Read this https://developer.hashicorp.com/packer/docs/provisioners/file#uploading-files-that-don-t-exist-before-packer-starts
  # New local script to first compile UERANSIM binaries if they are not present in the system
  provisioner "shell-local" {
    inline = [
      "appliances/UERANSIM/build.sh",
    ]
  }

  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.input_dir}/context",
      "${var.input_dir}/gen_context > ${var.input_dir}/context/context.sh",
      "mkisofs -o ${var.input_dir}/${var.appliance_name}-context.iso -V CONTEXT -J -R ${var.input_dir}/context",
    ]
  }
}


source "qemu" "UERANSIM" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "../one-apps/export/ubuntu2204.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  #skip_resize_disk = true
  disk_size        = "10240"        # default size increased to 10G

  output_directory = var.output_dir

  qemuargs = [
    ["-cpu", "host"],
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-context.iso"],
    ["-serial", "stdio"],
    # MAC addr needs to mach ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
  shutdown_command = "poweroff"
  vm_name          = "${var.appliance_name}"
}


build {
  sources = ["source.qemu.UERANSIM"]

  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",
      "../one-apps/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }

  provisioner "file" {
    sources = [
      "../one-apps/appliances/lib/common.sh",
      "../one-apps/appliances/lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }


  # Import UERANSIM binaries to path
  provisioner "file" {
    sources      = [
      "appliances/UERANSIM/UERANSIM/build/nr-gnb",
      "appliances/UERANSIM/UERANSIM/build/nr-ue",
      "appliances/UERANSIM/UERANSIM/build/nr-cli",
      "appliances/UERANSIM/UERANSIM/build/nr-binder",
    ]
    destination = "/usr/local/bin/"
  }
  # Import UERANSIM library to path
  provisioner "file" {
    sources      = [
      "appliances/UERANSIM/UERANSIM/build/libdevbnd.so",
    ]
    destination = "/usr/local/lib/"
  }
  # Import sample configuration files for the UERANSIM
  provisioner "shell" { inline = ["mkdir -p /etc/ueransim"] }
  provisioner "file" {
    source      = "appliances/UERANSIM/UERANSIM/config/open5gs-gnb.yaml"
    destination = "/etc/ueransim/open5gs-gnb-bak.yaml"
  }
  provisioner "file" {
    source      = "appliances/UERANSIM/UERANSIM/config/open5gs-ue.yaml"
    destination = "/etc/ueransim/open5gs-ue-bak.yaml"
  }


  provisioner "file" {
    sources     = [
      "appliances/UERANSIM/appliance.sh",
      ]
    destination = "/etc/one-appliance/service.d/"
  }

  #######################################################################
  # Setup appliance: Execute install step                               #
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#installation #
  #######################################################################
  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}
