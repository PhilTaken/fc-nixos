{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.redis;
  fclib = config.fclib;

  listen_addresses =
    fclib.listenAddresses "lo" ++
    fclib.listenAddresses "ethsrv";

  generatedPassword =
    lib.removeSuffix "\n" (readFile
      (pkgs.runCommand "redis.password" {}
      "${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 32 > $out"));

  password = lib.removeSuffix "\n" (
    if cfg.password == null
    then (fclib.configFromFile /etc/local/redis/password generatedPassword)
    else cfg.password
  );

  extraConfig = fclib.configFromFile /etc/local/redis/custom.conf "";

in {
  options = with lib; {

    flyingcircus.services.redis = {
      enable = mkEnableOption "Preconfigured Redis";

      password = mkOption {
        type = types.nullOr types.string;
        default = null;
        description = ''
          The password for redis. If null, a random password will be generated.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.redis;
        description = "The precise Redis package to use";
        example = "pkgs.redis";
      };
    };

  };

  config =
    lib.mkIf cfg.enable {

      services.redis.enable = true;
      services.redis.package = cfg.package;
      services.redis.requirePass = password;
      services.redis.bind = concatStringsSep " " listen_addresses;
      services.redis.extraConfig = extraConfig;


      flyingcircus.activationScripts.redis =
        lib.stringAfter [ "fc-local-config" ] ''
          if [[ ! -e /etc/local/redis/password ]]; then
            ( umask 007;
              echo ${lib.escapeShellArg password} > /etc/local/redis/password
              chown redis:service /etc/local/redis/password
            )
          fi
          chmod 0660 /etc/local/redis/password
        '';

      flyingcircus.localConfigDirs.redis = {
        dir = "/etc/local/redis";
        user = "redis";
      };

      systemd.services.redis = rec {
        serviceConfig = {
          LimitNOFILE = 64000;
          PermissionsStartOnly = true;
          Restart = "always";
        };

        after = [ "network.target" ];
        wants = after;
        preStart = "echo never > /sys/kernel/mm/transparent_hugepage/enabled";
        postStop = "echo madvise > /sys/kernel/mm/transparent_hugepage/enabled";
      };

      flyingcircus.services = {
        sensu-client.checks.redis = {
          notification = "Redis alive";
          command = ''
            ${pkgs.sensu-plugins-redis}/bin/check-redis-ping.rb \
              -h localhost -P ${lib.escapeShellArg password}
          '';
        };

        telegraf.inputs.redis = [
          {
            servers = [
              "tcp://:${password}@localhost:${toString config.services.redis.port}"
            ];
            # Drop string fields. They are converted to labels in Prometheus
            # which blows up the number of metrics.
            fielddrop = [
              "aof_last_bgrewrite_status"
              "aof_last_write_status"
              "maxmemory_policy"
              "rdb_last_bgsave_status"
              "used_memory_dataset_perc"
              "used_memory_peak_perc"
            ];
          }
        ];
      };

      boot.kernel.sysctl = {
        "vm.overcommit_memory" = 1;
        "net.core.somaxconn" = 512;
      };

      environment.etc."local/redis/README.txt".text = ''
        Redis is running on this machine.

        You can find the password for the redis in the `password`. You can also change
        the redis password by changing the `password` file.

        To change the redis configuration, add a file `custom.conf`, which will be
        appended to the redis configuration.
      '';

      # We want a fixed uid that is compatible with older releases.
      # Upstream doesn't set the uid.
      users.users.redis.uid = config.ids.uids.redis;
    };
}
