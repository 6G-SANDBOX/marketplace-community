source "null" "null" { communicator = "none" }

build {
  sources = ["source.null.null"]

  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.input_dir}/context",
      "${var.input_dir}/gen_context > ${var.input_dir}/context/context.sh",
      "mkisofs -o ${var.input_dir}/${var.appliance_name}-context.iso -V CONTEXT -J -R ${var.input_dir}/context",
    ]
  }
}

# A Virtual Machine is created with qemu in order to run the setup from the ISO on the CD-ROM
# Here are the details about the VM virtual hardware
source "qemu" "Collector_INT" {
  cpus        = 2 
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "../one-apps/export/ubuntu1804.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = "10240"

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

# Once the VM launches the following logic will be executed inside it to customize what happens inside
# Essentially, a bunch of scripts are pulled from ./appliances and placed inside the Guest OS
build {
  sources = ["source.qemu.Collector_INT"]

  # revert insecure ssh options done by context start_script
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]       # Set /etc/ssh/sshd_config with: PasswordAuthentication no, PermitRootLogin without-password, UseDNS no
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # Script Required by a further step
  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",     # script to execute '/etc/one-appliance/service configure' and 'bootstrap'
      "../one-apps/appliances/scripts/net-99-report-ready",          # when $REPORT_READY is YES, execute 'onegate vm update --data READY=YES' or a curl/wget equivalent
    ]
    destination = "/etc/one-appliance/"
  }

  # Bash libraries for easier custom implementation in bash logic. Contains multiple functions
  provisioner "file" {
    sources = [
      "../one-apps/appliances/lib/common.sh",
      "../one-apps/appliances/lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  # Contains the appliance service management tool, used to invoke the previous functions
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#appliance-life-cycle  
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }
  
  provisioner "file" {
    sources     = [
      "appliances/Collector_INT/appliance.sh"                   # main configuration script.
      ]
    destination = "/etc/one-appliance/service.d/"
  }

  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]   # execute '/etc/one-appliance/service install'
  }

  # Remove machine ID from the VM and get it ready for continuous cloud use
  # https://github.com/OpenNebula/one-apps/wiki/tool_dev#appliance-build-process
  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}