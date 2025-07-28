# null source, equivalent to applying the configuration to localhost.
source "null" "null" { communicator = "none" }

# Prior to setting up the appliance or distro, the context packages need to be generated first
# These will then be installed as part of the setup process
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
}

# A Virtual Machine is created with qemu in order to run the setup from the ISO on the CD-ROM
# Here are the details about the VM virtual hardware
source "qemu" "example" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "../one-apps/export/alma8.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  skip_resize_disk = true           # You can either 'skip_resize_disk = true' to use the "virtual disk" of the original image, or set to false and specify a fixed disk_size
  #disk_size        = "10240"       # I recommend the second approach as usually the original image is not large enough to fit all the added libraries and binaries.

  output_directory = var.output_dir

  qemuargs = [["-serial", "stdio"],
    ["-cpu", "host"],
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-context.iso"],
    # MAC addr needs to mach ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_wait_timeout = "900s"
  shutdown_command = "poweroff"
  vm_name          = "${var.appliance_name}"
}

# Once the VM launches the following logic will be executed inside it to customize what happens inside
# Essentially, a bunch of scripts are pulled from ./appliances and placed inside the Guest OS
# There are shared libraries for ruby and bash. Bash is used in this example
build {
  sources = ["source.qemu.example"]

  # revert insecure ssh options done by context start_script
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]       # Set /etc/ssh/sshd_config with: PasswordAuthentication no, PermitRootLogin without-password, UseDNS no
  }

  # creates directories for the new appliance files.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # imports network configuration scripts for OpenNebula CONTEXT.
  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",    # script to run '/etc/one-appliance/service configure' and 'bootstrap'.
      "../one-apps/appliances/scripts/net-99-report-ready",         # when $REPORT_READY is YES, run 'onegate vm update --data READY=YES' or a curl/wget equivalent.
    ]
    destination = "/etc/one-appliance/"
  }

  # imports bash libraries at appliances/lib for easier custom implementation in bash logic
  provisioner "file" {
    sources = [
      "../../lib/common.sh",
      "../../lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  # imports the appliance service management tool, which invokes the functions defined in the bash libraries.
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#appliance-life-cycle
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }

  
  #################################################################################################
  ###  BEGIN BLOCK:      'example'-specific steps to configure the appliance   ####################
  #################################################################################################

  # Pull your own custom logic here. Main script be called appliance.sh if using bash tools
  provisioner "file" {
    sources     = [                                   # locations of the file in the git repo. Flexible
      "../../appliances/.example/appliance.sh",                   # main configuration script.
      "../../appliances/.example/jenkins_plugins.txt",            # sample .txt file to import.
      "../../appliances/.example/jobs.yaml",                      # sample .yaml file to import.
      ]
    destination = "/etc/one-appliance/service.d/"          # path in the Guest OS. Strict, always the same
  }

  # Simpler appliance which needs no additional files, just the appliance.sh script
  # provisioner "file" {
  #   sources     = ["../../appliances/example/appliance.sh"]
  #   destination = "/etc/one-appliance/service.d/"
  # }

  #################################################################################################
  ###  END BLOCK:      'example'-specific steps to configure the appliance   ######################
  #################################################################################################

  # moves files net-*0 and net-99 to /etc/one-context and edit their permissions.
  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  # Setup appliance: Execute the install() step from appliance.sh
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#installation
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Remove machine ID from the VM and get it ready for continuous cloud use
  # https://github.com/OpenNebula/one-apps/wiki/tool_dev#appliance-build-process
  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["packer/postprocess.sh"]
  }
}
