{ config, pkgs, makeEnable, ... }:
makeEnable config "myModules.desktop" true {
  imports = [
    ./fonts.nix
  ];

  services.xserver = {
    exportConfiguration = true;
    enable = true;
    xkb = {
      layout = "us";
    };
    displayManager = {
      sessionCommands = ''
        systemctl --user import-environment GDK_PIXBUF_MODULE_FILE DBUS_SESSION_BUS_ADDRESS PATH
      '';
      setupCommands = ''
        autorandr -c
        systemctl restart autorandr.service
      '';
    };
  };

  services.autorandr = {
    enable = true;
  };

  # This is for the benefit of VSCODE running natively in wayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  services.gnome.at-spi2-core.enable = true;

  services.gnome.gnome-keyring.enable = true;

  environment.systemPackages = with pkgs; [
    # Appearance
    adwaita-icon-theme
    hicolor-icon-theme
    libsForQt5.breeze-gtk
    # materia-theme
    numix-icon-theme-circle
    papirus-icon-theme

    # XOrg
    autorandr
    wmctrl
    xclip
    xdotool
    xorg.xev
    xorg.xkbcomp
    xorg.xwininfo
    xsettingsd

    # Desktop
    alacritty
    blueman
    clipit
    d-spy
    dolphin

    feh
    firefox
    cheese
    gpaste
    kleopatra
    libnotify
    libreoffice
    lxappearance
    lxqt.lxqt-powermanagement
    networkmanagerapplet
    notify-osd-customizable
    okular
    pinentry
    mission-center
    quassel
    remmina
    rofi
    rofi-pass
    rofi-systemd
    shutter
    simplescreenrecorder
    skippy-xd
    synergy
    transmission_3-gtk
    vlc
    volnoti
    xfce.thunar

    # Audio
    picard
    playerctl
    pulsemixer
    espeak

    # Visualization
    graphviz
    nodePackages.mermaid-cli
  ] ++ (if pkgs.system == "x86_64-linux" then with pkgs; [
    google-chrome
    pommed_light
    slack
    spicetify-cli
    spotify
    tor-browser-bundle-bin
    vscode
    zulip
  ] else []);
}
