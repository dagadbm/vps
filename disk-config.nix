# Disk partitioning layout for Hetzner Cloud CX23 (40GB disk)
#
# Hetzner Cloud VMs use BIOS boot (not UEFI), so we need:
# 1. A small BIOS boot partition for GRUB's second stage
# 2. An EFI System Partition (for compatibility / future-proofing)
# 3. The root filesystem
#
# disko reads this config and partitions the disk automatically
# during nixos-anywhere deployment.
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            # GRUB needs this small partition to store its second-stage bootloader
            # on GPT-partitioned disks with BIOS boot
            boot = {
              size = "1M";
              type = "EF02"; # BIOS boot partition type
            };

            # EFI System Partition — mounted at /boot
            # FAT32 formatted, holds kernel and initrd
            ESP = {
              size = "512M";
              type = "EF00"; # EFI System Partition type
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };

            # Root partition — uses all remaining disk space
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
