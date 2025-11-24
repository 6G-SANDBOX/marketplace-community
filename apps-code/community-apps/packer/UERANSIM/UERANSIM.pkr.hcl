source "null" "null" { communicator = "none" }

build {
  sources = ["source.null.null"]

  # Generate temporal CONTEXT .iso file to be able to login into the source VM.
  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.input_dir}/context",
      "${var.input_dir}/gen_context > ${var.input_dir}/context/context.sh",
      "mkisofs -o ${var.input_dir}/${var.appliance_name}-context.iso -V CONTEXT -J -R ${var.input_dir}/context",
    ]
  }

  # Compile the latest UERANSIM binaries if not present, or their source code changed.
  provisioner "shell-local" {
    inline = [
      "bash ../../appliances/UERANSIM/build.sh",
    ]
  }
}

source "qemu" "UERANSIM" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "../one-apps/export/debian12.qcow2"
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


  #################################################################################################
  ###  BEGIN BLOCK:      UERANSIM-specific steps to configure the appliance   #####################
  #################################################################################################

  # Import the appliance.sh along with some helper files to the appliance VM.
  provisioner "file" {
    sources     = [
      "../../appliances/UERANSIM/appliance.sh",
      "../../appliances/UERANSIM/gnb-mappings.json",
      "../../appliances/UERANSIM/ue-mappings.json",
      ]
    destination = "/etc/one-appliance/service.d/"
  }

  # Create directories for UERANSIM files.
  provisioner "shell" { inline = ["mkdir -p /etc/ueransim /tmp/.UERANSIM/build /tmp/.UERANSIM/config"] }

  # Import UERANSIM binaries and libraries to the appliance VM.
  provisioner "file" {
    source      = "../../appliances/UERANSIM/.files/build/"
    destination = "/tmp/.UERANSIM/build"
  }
  # Move the binaries and libraries to their right path.
  provisioner "shell" {
    inline = [
      "mv /tmp/.UERANSIM/build/libdevbnd.so /usr/local/lib/",
      "mv /tmp/.UERANSIM/build/* /usr/local/bin/"
    ]
  }

  # Import UERANSIM sample config files to the appliance VM.
  provisioner "file" {
    source      = "../../appliances/UERANSIM/.files/config/"
    destination = "/tmp/.UERANSIM/config"
  }
  # Move the sample config files to their right path.
  provisioner "shell" {
    inline = [
      "mv /tmp/.UERANSIM/config/open5gs-gnb.yaml /etc/ueransim/open5gs-gnb-original.yaml",
      "mv /tmp/.UERANSIM/config/open5gs-ue.yaml  /etc/ueransim/open5gs-ue-original.yaml"
    ]
  }

  # Cleanup temporary files.
  provisioner "shell" { inline = ["rm -rf /tmp/.UERANSIM"] }

  #################################################################################################
  ###  END BLOCK:      UERANSIM-specific steps to configure the appliance   #######################
  #################################################################################################


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
    scripts = ["packer/postprocess.sh"]
  }
}
