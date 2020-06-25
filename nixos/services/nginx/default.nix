{ lib, config, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.nginx;
  fclib = config.fclib;

  nginxCheckConfig = pkgs.writeScriptBin "nginx-check-config" ''
    $(systemctl cat nginx | grep "X-CheckConfigCmd" | cut -d= -f2)
  '';

  nginxShowConfig = pkgs.writeScriptBin "nginx-show-config" ''
    cat $(systemctl cat nginx | grep "X-ConfigFile" | cut -d= -f2)
  '';

  nginxCheckWorkerAge = pkgs.writeScript "nginx-check-worker-age" ''
    config_age=$(expr $(date +%s) - $(stat --format=%Y /run/nginx/config) )
    main_pid=$(systemctl show nginx | grep -e '^MainPID=' | cut -d= -f 2)

    workers_too_old=0

    for pid in $(pgrep -P $main_pid); do
        worker_age=$(ps -o etimes= $pid)
        agediff=$(expr $worker_age - $config_age)

        # We want to ignore workers that are already shutting down after a reload request.
        # They don't accept new connections and should get killed after worker_shutdown_timeout expires.
        shutting_down=$(ps --no-headers $pid | grep 'shutting down')

        if [[ $agediff -gt 1 && -z $shutting_down ]]; then
            start_time=$(ps -o lstart= $pid)
            echo "Worker process $pid is $agediff seconds older than the config file (started $start_time)"
            workers_too_old=1
        fi
    done

    if (( $workers_too_old > 0 )); then
        exit 2
    else
        echo "worker age OK"
    fi
  '';

  stateDir = config.services.nginx.stateDir;
  package = config.services.nginx.package;
  localDir = config.flyingcircus.localConfigDirs.nginx.dir;

  vhostsJSON = fclib.jsonFromDir localDir;

  virtualHosts = lib.mapAttrs (
    _: val:
    (lib.optionalAttrs
      ((val ? addSSL || val ? onlySSL || val ? forceSSL))
      { enableACME = true; }) // removeAttrs val [ "emailACME" ])
    vhostsJSON;

  # only email setting supported at the moment
  acmeSettings =
    lib.mapAttrs (name: val: { email = val.emailACME; })
    (lib.filterAttrs (_: val: val ? emailACME ) vhostsJSON);

  acmeVhosts = (lib.filterAttrs (_: val: val ? enableACME ) vhostsJSON);

  mainConfig = ''
    worker_processes ${toString (fclib.currentCores 1)};
    worker_rlimit_nofile 8192;
    worker_shutdown_timeout ${toString cfg.workerShutdownTimeout};
  '';

  baseHttpConfig = ''
    # === Defaults ===
    default_type application/octet-stream;
    charset UTF-8;

    # === Logging ===
    map $remote_addr $remote_addr_anon_head {
      default 0.0.0;
      "~(?P<ip>\d+\.\d+\.\d+)\.\d+" $ip;
      "~(?P<ip>[^:]+:[^:]+:[^:]+):" $ip;
    }
    map $remote_addr $remote_addr_anon_tail {
      default .0;
      "~(?P<ip>\d+\.\d+\.\d+)\.\d+" .0;
      "~(?P<ip>[^:]+:[^:]+:[^:]+):" ::;
    }
    map $remote_addr_anon_head$remote_addr_anon_tail $remote_addr_anon {
        default 0.0.0.0;
        "~(?P<ip>.*)" $ip;
    }

    # same as 'anonymized'
    log_format main
        '$remote_addr_anon - $remote_user [$time_local] '
        '"$request" $status $bytes_sent '
        '"$http_referer" "$http_user_agent" '
        '"$gzip_ratio"';
    log_format anonymized
        '$remote_addr_anon - $remote_user [$time_local] '
        '"$request" $status $body_bytes_sent '
        '"$http_referer" "$http_user_agent" '
        '"$gzip_ratio"';
    log_format nonanonymized
        '$remote_addr - $remote_user [$time_local] '
        '"$request" $status $bytes_sent '
        '"$http_referer" "$http_user_agent" '
        '"$gzip_ratio"';
    log_format performance
        '$time_iso8601 $pid.$connection.$connection_requests '
        '$request_method "$scheme://$host$request_uri" $status '
        '$bytes_sent $request_length $pipe $request_time '
        '"$upstream_response_time" $gzip_ratio';

    open_log_file_cache max=64;
    access_log /var/log/nginx/access.log anonymized;
    access_log /var/log/nginx/performance.log performance;

    # === Buffers and timeouts ===
    client_body_timeout 10m;
    client_header_buffer_size 4k;
    client_header_timeout 10m;
    connection_pool_size 256;
    large_client_header_buffers 4 16k;
    request_pool_size 4k;
    send_timeout 10m;
    server_names_hash_bucket_size ${toString cfg.mapHashBucketSize};
  '';

  plainConfigFiles = filter (p: lib.hasSuffix ".conf" p) (fclib.files localDir);
  localHttpConfig = concatStringsSep "\n" (map readFile plainConfigFiles);

in
{
  options.flyingcircus.services.nginx = with lib; {
    enable = mkEnableOption "FC-customized nginx";

    httpConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Configuration lines to be appended inside of the http {} block.
      '';
    };

    mapHashBucketSize = mkOption {
      type = types.int;
      default = 64;
      description = "Bucket size for the 'map' variables hash tables.";
    };

    workerShutdownTimeout = mkOption {
      type = types.int;
      default = 240;
      description = ''
        Configures a timeout (seconds) for a graceful shutdown of worker processes.
        When the time expires, nginx will try to close all the connections currently
        open to facilitate shutdown.
        By default, nginx will try to close connections 4 minutes after a reload.
      '';
    };

  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      environment.etc = {
        "local/nginx/README.txt".source = ./README.txt;

        "local/nginx/fastcgi_params" = {
          source = "${package}/conf/fastcgi_params";
        };

        "local/nginx/uwsgi_params" = {
          source = "${package}/conf/uwsgi_params";
        };

        # file has moved; link back to the old location for compatibility reasons
        "local/nginx/htpasswd_fcio_users" = {
          source = "/etc/local/htpasswd_fcio_users";
        };

        "local/nginx/example-configuration".text =
          import ./example-config.nix { inherit config lib; };

        "local/nginx/modsecurity/README.txt".text = ''
          Here are example configuration files for ModSecurity.

          You need to adapt them to your needs *and* provide a ruleset. A common
          ruleset is the OWASP ModSecurity Core Rule Set (CRS) (https://www.modsecurity.org/crs/).
          You can get it via:

            git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git

          Save the adapted ruleset in a subdirectory here and adjust
          modsecurity_includes.conf.
        '';

        "local/nginx/modsecurity/modsecurity.conf.example".source =
          ./modsecurity.conf;

        "local/nginx/modsecurity/modsecurity_includes.conf.example".source =
          ./modsecurity_includes.conf;

        "local/nginx/modsecurity/unicode.mapping".source =
          "${pkgs.modsecurity_standalone.nginx}/unicode.mapping";
      };

      flyingcircus.services.telegraf.inputs = {
        nginx = [ {
          urls = [ "http://localhost/nginx_status" ];
        } ];
      };

      flyingcircus.services.sensu-client.checks = {

        nginx_config = {
          notification = "Nginx configuration check problems";
          command = "/run/wrappers/bin/sudo ${nginxCheckConfig}/bin/nginx-check-config || exit 2";
          interval = 300;
        };

        nginx_status = {
          notification = "nginx does not listen on port 80";
          command = ''
            ${pkgs.monitoring-plugins}/bin/check_http \
              -H localhost -u /nginx_status -s server -c 5 -w 2
          '';
          interval = 60;
        };

        nginx_worker_age = {
          notification = "worker processes are older than config file";
          command = "${nginxCheckWorkerAge}";
          interval = 300;
        };

      } //
      (lib.mapAttrs' (name: _: (lib.nameValuePair "nginx_cert_${name}" {
        notification = "HTTPS cert for ${name} (Let's encrypt)";
        command = "${pkgs.monitoring-plugins}/bin/check_http -H ${name} -p 443 -S -C 5";
        interval = 600;
      })) acmeVhosts);

      networking.firewall.allowedTCPPorts = [ 80 443 ];

      security.acme.certs = acmeSettings;

      flyingcircus.passwordlessSudoRules = [
        # sensuclient can run config check script as nginx user
        {
          commands = [ "${nginxCheckConfig}/bin/nginx-check-config" ];
          groups = [ "sensuclient" ];
        }
      ];

      services.nginx = {
        enable = true;
        appendConfig = mainConfig;
        appendHttpConfig = ''
          ${baseHttpConfig}

          # === User-provided config from ${localDir}/*.conf ===
          ${localHttpConfig}

          # === Config from flyingcircus.services.nginx ===
          ${cfg.httpConfig}
        '';

        eventsConfig = ''
          worker_connections 4096;
          multi_accept on;
        '';
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        statusPage = true;
        inherit virtualHosts;
      };

      services.logrotate.config = ''
        /var/log/nginx/*.log
        {
            rotate 92
            create 0644 nginx service
            postrotate
                systemctl kill nginx -s USR1 --kill-who=main || systemctl restart nginx
            endscript
        }
      '';

      # Config check fails on first run if /var/spool/nginx/logs is missing.
      # Nginx creates it, but we create it here to avoid that useless error.
      # It's only used on Nginx startup, "real" logging goes to /var/log/nginx.
      systemd.tmpfiles.rules = [
        "d /var/log/nginx 0755 nginx"
        "d /var/spool/nginx/logs 0755 nginx nginx 7d"
        "d /etc/local/nginx/modsecurity 2775 nginx service"
      ];

      flyingcircus.localConfigDirs.nginx = {
        dir = "/etc/local/nginx";
        user = "nginx";
      };

      environment.systemPackages = [
        nginxCheckConfig
        nginxShowConfig
      ];

    })
  ];
}
