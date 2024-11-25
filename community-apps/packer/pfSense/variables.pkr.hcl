variable "appliance_name" {
  type    = string
  default = "pfSense"
}

variable "version" {
  type    = string
  default = "272"
}

variable "input_dir" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "headless" {
  type    = bool
  default = false
}

variable "pfSense" {
  type = map(object({ 
    iso_url = string,
    iso_checksum = string
  }))

  default = {
    "272" = {
      iso_url      = "https://repo.ialab.dsu.edu/pfsense/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
      iso_checksum = "https://repo.ialab.dsu.edu/pfsense/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz.sha256"
    }
  }
}

variable "boot_cmd" {
  type = map(list(string))

  default = {
    "13" = [
      "I<wait>",       # Welcome: Install
      "<enter><wait>", # Keymap Selection: Continue with default

      "localhost", # Set hostname
      "<enter><wait>",

      "<enter><wait>", # Distribution Select

      "<down><enter><wait>",                       # Partitioning, Auto (UFS)
      "E<wait>",                                   # Entire Disk
      "G<enter><wait>",                            # GPT
      "<down><down><down>D<wait>",                 # Delete swap partition
      "M<wait>",                                   # Modify second partition
      "<tab><tab><down><down>rootfs<enter><wait>", # Set rootfs label on root p.
      "F<wait>",                                   # Finish
      "C<wait>",                                   # Commit
      "<wait2m30s>",                               # Wait for base install

      "opennebula<enter><wait>", # Root password
      "opennebula<enter><wait>",

      "<enter><wait>", # Network, vtnet0
      "Y<wait>",       # IPv4 yes
      "Y<wait10>",     # DHCP yes
      "N<wait>",       # IPv6 no
      "<enter><wait>", # Resolver configuration

      "0<enter><wait>", # Time zone selector
      "Y<wait>",        # UTC
      "S<wait>",        # Skip date
      "S<wait>",        # Skip time

      "<enter><wait>", # System Configuration, OK
      "<enter><wait>", # System Hardening, OK

      "N<wait>",          # Add User Accounts, no
      "E<enter><wait10>", # Final Configuration, exit
      "Y<wait>",          # Yes

      # Manual Configuration
      "sed -i '' -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config<enter><wait>",
      "sed -i '' -e 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config<enter><wait>",
      "sed -i '' -e 's/^.*\\([[:space:]]\\/[[:space:]]\\)/\\/dev\\/gpt\\/rootfs\\1/' /etc/fstab<enter><wait>",
      "sync<enter>exit<enter><wait>",

      "R<wait10>" # Complete: Reboot
    ]

    "14" = [
      "I<wait7s>",       # Welcome: Install
      "<enter><wait2s>", # Keymap Selection: Continue with default

      "localhost",     # Set hostname
      "<enter><wait2s>",

      "<enter><wait2s>", # Distribution Select

      "<down><enter><wait2s>",                     # Partitioning, Auto (UFS)
      "E<wait2s>",                                   # Entire Disk
      "G<enter><wait2s>",                            # GPT
      "<down><down><down>D<wait>",                 # Delete swap partition
      "M<wait>",                                   # Modify second partition
      "<down><down><down>rootfs<tab><enter>",      # Set rootfs label on root p.
      "F<wait>",                                   # Finish
      "C<wait>",                                   # Commit
      "<wait5m>",                               # Wait for base install

      "opennebula<enter><wait2s>", # Root password
      "opennebula<enter><wait5s>",

      "<enter><wait2s>", # Network, vtnet0
      "Y<wait2s>",       # IPv4 yes
      "Y<wait10>",       # DHCP yes
      "N<wait2s>",       # IPv6 no
      "<enter><wait2s>", # Resolver configuration

      "11<enter><wait2s>", # Time zone selector
      "Y<wait>",           # UTC
      "S<wait>",           # Skip date
      "S<wait>",           # Skip time

      "<enter><wait2s>", # System Configuration, OK
      "<enter><wait2s>", # System Hardening, OK

      "N<wait>",          # Add User Accounts, no
      "E<enter><wait10>", # Final Configuration, exit
      "Y<wait>",          # Yes

      # Manual Configuration
      "sed -i '' -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config<enter><wait>",
      "sed -i '' -e 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config<enter><wait>",
      "sed -i '' -e 's/^.*\\([[:space:]]\\/[[:space:]]\\)/\\/dev\\/gpt\\/rootfs\\1/' /etc/fstab<enter><wait>",
      "sync<enter>exit<enter><wait2s>",

      "R<wait10>" # Complete: Reboot
    ]
  }
}