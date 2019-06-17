# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ../configuration.nix
    ../extra.nix
    ../dfinity.nix
    /etc/nixos/cachix.nix
  ];

  hardware.bumblebee = {
    enable = true;
    pmMethod = "bbswitch";
  };

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.xserver.libinput.enable = true;

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/58218a04-3ba1-4295-86bb-ada59f75e3b6";
    fsType = "ext4";
  };

  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/8142784e-45c6-4a2b-91f1-09df741ac00f";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/36E1-BE93";
    fsType = "vfat";
  };

  systemd.services.resume-fix = {
    description = "Fixes acpi immediate resume after suspend";
    wantedBy = [ "multi-user.target" "post-resume.target" ];
    after = [ "multi-user.target" "post-resume.target" ];
    script = ''
      if ${pkgs.gnugrep}/bin/grep -q '\bXHC\b.*\benabled\b' /proc/acpi/wakeup; then
      echo XHC > /proc/acpi/wakeup
      fi
    '';
    serviceConfig.Type = "oneshot";
  };

  swapDevices = [ ];

  networking.hostName = "ivanm-dfinity-razer";

  nix.maxJobs = lib.mkDefault 12;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
