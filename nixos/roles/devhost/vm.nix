{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.roles.devhost;
  location = lib.attrByPath [ "parameters" "location" ] "" config.flyingcircus.enc;

  vmOptions = {
    options = {
      id = mkOption {
        description = "Internal ID of the VM";
        type = types.int;
      };
      memory = mkOption {
        description = "Memory assigned to the VM";
        type = types.str;
        example = "1024M";
      };
      cpu = mkOption {
        description = "CPU cores assigned to the VM";
        type = types.int;
        example = 2;
      };
      aliases = mkOption {
        description = "Aliases set in the nginx proxy, forwarding to the VM";
        type = types.listOf types.str;
        default = [];
      };
      srvIp = mkOption {
        description = "IP of the VM on the SRV interface";
        type = types.str;
      };
      srvMac = mkOption {
        description = "MAC Address of the VM on the SRV interface";
        type = types.str;
      };
    };
  };

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
        "-cpu" "host"
        "-smp" vmCfg.cpu
        "-m" vmCfg.memory
        "-nodefaults"
        "-no-user-config"
        "-nographic"
        "-drive" "id=root,format=qcow2,file=/var/lib/devhost/vms/${name}/rootfs.qcow2,if=virtio,aio=threads"
        "-netdev" "tap,id=ethsrv-${name},ifname=vm-srv-${name},script=${ifaceUpScript},downscript=${ifaceDownScript}"
        "-device" "virtio-net,netdev=ethsrv-${name},mac=${vmCfg.srvMac}"
        "-serial" "file:/var/lib/devhost/vms/${name}/log"
      ]);
  });

  # We unfortunately cannot use writePython3Bin as that only supports
  # python libs in path, and not other applications.
  # XXX: Switch to the following code with 23.05
  # manage_script = pkgs.writeShellApplication {
  #   name = "fc-manage-dev-vms";
  #   runtimeInputs = with pkgs; [
  #     xfsprogs
  #     qemu
  #     python3.withPackages (ps: with ps; [ requests ])
  #   ];
  #   text = "python ${./fc-manage-dev-vms.py}";
  # };
  manage_script = let 
    runtimeInputs = with pkgs; [
      (python3.withPackages(ps: with ps; [ requests ]))
      xfsprogs
      qemu
    ];
  in pkgs.writeTextFile rec {
    name = "fc-manage-dev-vms";
    executable = true;
    destination = "/bin/${name}";
    text = ''
      #!${pkgs.runtimeShell}
      set -o errexit
      set -o nounset
      set -o pipefail

      if [[ ! -f "/var/lib/devhost/ssh_bootstrap_key" ]]; then
         cat > /var/lib/devhost/ssh_bootstrap_key <<EOF
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
  QyNTUxOQAAACBnO1dnNsxT0TJfP4Jgb9fzBJXRLiWrvIx44cftqs4mLAAAAJjYNRR+2DUU
  fgAAAAtzc2gtZWQyNTUxOQAAACBnO1dnNsxT0TJfP4Jgb9fzBJXRLiWrvIx44cftqs4mLA
  AAAEDKN3GvoFkLLQdFN+Blk3y/+HQ5rvt7/GALRAWofc/LFGc7V2c2zFPRMl8/gmBv1/ME
  ldEuJau8jHjhx+2qziYsAAAAEHJvb3RAY3QtZGlyLWRldjIBAgMEBQ==
  -----END OPENSSH PRIVATE KEY-----
  EOF
        chmod 600 /var/lib/devhost/ssh_bootstrap_key
      fi

      export PATH="${makeBinPath runtimeInputs}:$PATH"
      python ${./fc-manage-dev-vms.py} "$@" --location ${location}
    '';
  };
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
  config = mkIf (cfg.enable && cfg.virtualisationType == "vm") {
    boot.kernelModules = [ "nbd" ];
    boot.extraModprobeConfig = ''
      options nbd max_part=4 nbds_max=8
    '';

    environment.systemPackages = [ manage_script ];
    security.sudo.extraRules = mkAfter [{
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
            { address = "10.12.0.1"; prefixLength = 16; }
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

        dhcp-range=10.12.12.10,10.12.12.254,255.255.240.0,24h
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
    networking.extraHosts = ''
      # static entries for devhost vms to avoid nginx issues
      # if containers are not running and to use the existing batou ssh configs.
    '' + (concatStringsSep "\n" (mapAttrsToList (vmName: vmCfg: "${vmCfg.srvIp} ${vmName}") cfg.virtualMachines));
  };
}
