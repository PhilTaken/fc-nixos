{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.roles.devhost;

  vmOptions = {
    options = {
      memory = mkOption {
        description = "Memory assigned to the VM";
        type = types.str;
        example = "1024M";
      };
      cores = mkOption {
        description = "CPU cores assigned to the VM";
        type = types.int;
        example = 2;
      };
      aliases = mkOption {
        description = "Aliases set in the nginx proxy, forwarding to the VM";
        type = types.listOf types.str;
        default = [];
      };
    };
  };

  addColons = text: lib.concatStringsSep ":" (lib.genList (x: lib.substring (x * 2) 2 text) ((lib.stringLength text) / 2));
  convertNameToMAC = name: vlanId: "02:${vlanId}:" + (addColons (lib.substring 0 8 (builtins.hashString "md5" name)));

  ifaceUpScript = pkgs.writeShellScript "fc-devhost-vm-iface-up" ''
    ${pkgs.iproute2}/bin/ip tuntap add name $1 mode tap
    ${pkgs.iproute2}/bin/ip link set $1 up
    sleep 0.2s
    ${pkgs.iproute2}/bin/ip link set $1 master br-vm-srv
  '';
  ifaceDownScript = pkgs.writeShellScript "fc-devhost-vm-iface-down" ''
    sleep 0.2s
    ${pkgs.iproute2}/bin/ip tuntap del name $1 mode tap
  '';

  defaultService = {
    description = "FC dev Virtual Machine '%i'";
    path = [ pkgs.qemu_kvm ];
    serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
  };
  mkService = name: vmCfg: nameValuePair "fc-devhost-vm@${name}" (recursiveUpdate defaultService {
    enable = true;
    wantedBy = [ "machines.target" ];

    serviceConfig.ExecStart = (escapeShellArgs
      [
        "${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
        "-name" name
        "-enable-kvm"
        "-smp" vmCfg.cores
        "-m" vmCfg.memory
        "-nodefaults"
        "-no-user-config"
        "-no-reboot"
        "-nographic"
        "-drive" "id=root,format=qcow2,file=/var/lib/devhost/vms/${name}/rootfs.qcow2,if=virtio,aio=threads"
        "-netdev" "tap,id=ethsrv-${name},ifname=vm-srv-${name},script=${ifaceUpScript},downscript=${ifaceDownScript}"
        "-device" "virtio-net,netdev=ethsrv-${name},mac=${convertNameToMAC name "03"}"
        "-serial" "file:/var/lib/devhost/vms/${name}/log"
      ]);
  });

  manage_script = pkgs.writeShellScriptBin "fc-manage-dev-vms" ''
    # XXX this needs to become/invoke the fc-manage-dev-vms script
  '';
in {
  options = {
    flyingcircus.roles.devhost = {
      virtualMachines = mkOption {
        description = ''
          Description of devhost virtual machines. This config will be auto-generated by batou.
          Only of relevance when `flyingcircus.roles.devhost.virtualisationType = "vm"`.
        '';
        type = types.attrsOf (types.submodule vmOptions);
        default = {};
      };
    };
  };
  config = lib.mkIf (cfg.enable && cfg.virtualisationType == "vm") {
    environment.systemPackages = [ manage_script ];
    security.sudo.extraRules = lib.mkAfter [{
      commands = [{
        command = "${manage_script}/bin/fc-manage-dev-vms";
        options = [ "NOPASSWD" ];
      }];
      groups = [ "service" "users" ];
    }];
    # FIXME: Align network interface names with production
    networking = {
      bridges."br-vm-srv" = {
        interfaces = [];
      };
      interfaces = {
        "br-vm-srv" = {
          ipv4.addresses = [
            { address = "10.12.0.1"; prefixLength = 20; }
          ];
        };
      };
      nat = {
        enable = true;
        enableIPv6 = true;
        internalInterfaces = [ "br-vm-srv" ];
      };
    };
    services.dnsmasq = {
      enable = true;
      # FIXME: Either use the hosts dnsmasq or the correct rz nameservers
      extraConfig = ''
        interface=br-vm-srv

        dhcp-range=10.12.0.10,10.12.12.254,255.255.240.0,24h
        dhcp-option=option:router,10.12.0.1
        dhcp-option=6,8.8.8.8
      '';
    };
    networking.firewall.interfaces."br-vm-srv".allowedUDPPorts = [ 67 ];
    networking.firewall.interfaces."vm-srv+".allowedUDPPorts = [ 67 ];
    systemd.services = {
      "fc-devhost-vm@" = defaultService;
    } // mapAttrs' mkService cfg.virtualMachines;

    services.nginx.virtualHosts = if cfg.enableAliasProxy then
      (let
        suffix = cfg.publicAddress;
        vms =
          filterAttrs (name: vmCfg: vmCfg.aliases != [ ]) cfg.virtualMachines;
        generateVhost = vmName: vmCfg: nameValuePair "${vmName}.${suffix}" {
          serverAliases = map (alias: "${alias}.${vmName}.${suffix}") vmCfg.aliases;
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "https://${vmName}";
          };
        };
      in (mapAttrs' generateVhost vms))
    else
      { };
  };
}
