{ lib, ... }:
let
  modulesFromHere = [
    "services/misc/gitlab.nix"
    "services/monitoring/prometheus/default.nix"
    "services/monitoring/prometheus.nix"
    "services/networking/jicofo.nix"
    "services/networking/jitsi-videobridge.nix"
    "services/web-servers/nginx/default.nix"
  ];

in {
  disabledModules = modulesFromHere;

  imports = with lib; [
    ./box/client.nix
    ./collectdproxy.nix
    ./gitlab
    ./graylog.nix
    ./haproxy.nix
    ./jitsi/jicofo.nix
    ./jitsi/jitsi-videobridge.nix
    ./logrotate
    ./nginx
    ./nullmailer.nix
    ./percona.nix
    ./postgresql.nix
    ./prometheus.nix
    ./rabbitmq36.nix
    ./rabbitmq.nix
    ./redis.nix
    ./sensu.nix
    ./syslog.nix
    ./telegraf.nix

    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ];
}
