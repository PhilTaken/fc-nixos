{ config, lib, pkgs, ... }:

with builtins;
with lib;

let
  params = lib.attrByPath [ "parameters" ] {} config.flyingcircus.enc;
  fclib = config.fclib;
  roles = config.flyingcircus.roles;

  listenFe = fclib.network.fe.dualstack.addresses;
  listenFe4 = fclib.network.fe.v4.addresses;
  listenFe6 = fclib.network.fe.v6.addresses;
  listenSrv = fclib.network.srv.dualstack.addresses;
  listenSrv4 = fclib.network.fe.v4.addresses;
  listenSrv6 = fclib.network.fe.v6.addresses;
  hasFE = (params ? location &&
    lib.hasAttrByPath [ "interfaces" "fe" ] params &&
    listenFe4 != [] && listenFe6 != []);

  stdOptions = {

    mailHost = mkOption {
      type = types.str;
      default = with config.networking; if hasFE
        then "${hostName}.fe.${params.location}.${domain}"
        else if domain != null then "${hostName}.${domain}" else hostName;
      description = ''
        FQDN of the mail server's frontend address. IP adresses and
        forward/reverse DNS must match exactly.
      '';
      example = "mail.example.com";
    };

    rootAlias = mkOption {
      type = types.str;
      description = "Address to receive all mail to root@localhost.";
      default = "admin@flyingcircus.io";
    };

    smtpBind4 = mkOption {
      type = types.str;
      description = ''
        IPv4 address for outgoing connections. Must match forward/reverse DNS.
      '';
      default = if hasFE then head listenFe4 else
                if listenSrv4 != [] then head listenSrv4 else "";
    };

    smtpBind6 = mkOption {
      type = types.str;
      description = ''
        IPv6 address for outgoing connections. Must match forward/reverse DNS.
      '';
      default = if hasFE then head listenFe6 else
                if listenSrv6 != [] then head listenSrv6 else "";
    };

    explicitSmtpBind = mkOption {
      type = types.bool;
      description = ''
        Whether to include smtp_bind_address* statements explicitely in
        main.cf or not. Set to false in case mail must be relayed both to the
        public Internet and to other nodes inside the RG via srv.
      '';
      default = (length listenFe4 > 1) || (length listenFe6 > 1);
    };

    dynamicMaps = mkOption {
      description = ''
      '';
      type = with types; attrsOf (listOf path);
      default = {};
      example = {
        virtual_alias_maps = [ "/srv/test/valias" ];
      };
    };

  };

in
{
  imports = [
    ../services/mail
  ];

  options = {

    flyingcircus.roles.mailserver = with lib; stdOptions // {
      enable = mkEnableOption ''
        Flying Circus mailserver role with web mail.
        Mailout on all nodes in this RG/location.
      '';

      # this allows finegrained control over each domain
      # for example domain."test.fcio.net".autoconfig = false;
      domains = mkOption {
        type = with types; either (types.attrsOf (types.submodule {
          options = {
            enable = mkOption {
              description = "Enable mail services for this domain";
              default = true;
              type = types.bool;
            };

            primary = mkOption {
              description = "Make this domain the primary mail domain";
              default = false;
              type = types.bool;
            };

            autoconfig = mkOption {
              description = "Enable autoconfig host for this domain";
              default = true;
              type = types.bool;
            };
          };
        })) (listOf str);

        description = ''
          Mail domain configuration
        '';

        example = {
          "your-company.tld" = {
            primary = true;
          };

          "newsletter.your-company.tld" = {
            autoconfig = false;
          };
        };

        apply = v: (if isList v then
          trace ''
            WARN: Using outdated domains = [] list. Please upgrade to the new format
              {
                "domain.tld" = {
                  primary = true;
                };
              }
          ''
          recursiveUpdate
            (listToAttrs (map (domain: (nameValuePair domain { enable = true; autoconfig = true;})) v))
            (optionalAttrs (v != []) { "${head v}" = { primary = true; }; })
          else v);
      };

      webmailHost = mkOption {
        type = with types; nullOr str;
        description = "(Virtual) host name of the webmail service.";
        example = "webmail.example.com";
        default = null;
      };

      redisDatabase = mkOption {
        type = types.int;
        description = ''
          Redis DB id to store spam-related data. Should be set to an unique
          number (machine-local )to avoid conflicts.
        '';
        default = 5;
      };

      passwdFile = mkOption {
        type = types.str;
        description = "Virtual mail user passwd file (shared Postfix/Dovecot)";
        default = "/var/lib/dovecot/passwd";
      };

    };

    flyingcircus.roles.mailstub = with lib; stdOptions // {
      enable = mkEnableOption ''
        Flying Circus mail stub role which creates a simple Postfix instance for
        manual configuration.
      '';
    };
  };

  config = lib.mkMerge [

    (lib.mkIf roles.mailserver.enable {
      flyingcircus.services.mail.enable = assert !roles.mailstub.enable; true;
      flyingcircus.services.nginx.enable = true;
      flyingcircus.services.redis.enable = true;

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [ "${pkgs.postfix}/bin/postsuper" ];
          groups = [ "sudo-srv" "service" ];
        }
      ];

      flyingcircus.roles.mailserver =
        fclib.jsonFromFile "/etc/local/mail/config.json" "{}";
    })

    (lib.mkIf roles.mailstub.enable {
      flyingcircus.services.postfix.enable =
        assert !roles.mailserver.enable; true;
    })

    (lib.mkIf (!roles.mailserver.enable && !roles.mailstub.enable) {
      flyingcircus.services.nullmailer.enable = true;
    })

  ];

  # For all mail related service definitions, see nixos/services/mail/*
}
