{ config, lib, pkgs, ... }:

with builtins;

let
  params = lib.attrByPath [ "parameters" ] {} config.flyingcircus.enc;
  fclib = config.fclib;
  roles = config.flyingcircus.roles;

  listenFe = fclib.listenAddresses "ethfe";
  listenFe4 = filter fclib.isIp4 listenFe;
  listenFe6 = filter fclib.isIp6 listenFe;
  listenSrv = fclib.listenAddresses "ethsrv";
  listenSrv4 = filter fclib.isIp4 listenSrv;
  listenSrv6 = filter fclib.isIp6 listenSrv;
  hasFE = (params ? location &&
    lib.hasAttrByPath [ "interfaces" "fe" ] params &&
    listenFe4 != [] && listenFe6 != []);

  stdOptions = with lib; {

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

      domains = mkOption {
        type = types.listOf types.str;
        example = [ "example.com" ];
        default = [];
        description = ''
          List of virtual domains that this mail server serves. The first value
          is the canonical domain used to construct internal addresses in
          various places.
        '';
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
