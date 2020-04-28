{ config, lib, pkgs, ... }:

with builtins;

let
  params = lib.attrByPath [ "parameters" ] {} config.flyingcircus.enc;
  fclib = config.fclib;
  role = config.flyingcircus.roles.mailserver;

  listenFe = fclib.listenAddresses "ethfe";
  listenFe4 = filter fclib.isIp4 listenFe;
  listenFe6 = filter fclib.isIp6 listenFe;

  # default domain should be changed to to fcio.net once #14970 is finished
  defaultFQDN =
    if (params ? location &&
        lib.hasAttrByPath [ "interfaces" "fe" ] params &&
        (length listenFe > 0))
    then "${config.networking.hostName}.fe.${params.location}.fcio.net"
    else "${config.networking.hostName}.fcio.net";

in
{
  imports = [
    ../services/mail
  ];

  options = {

    flyingcircus.roles.mailserver = with lib; {
      # The mailserver role was/is thought to implement an entire mailserver,
      # and would be billed as component.

      enable = mkEnableOption ''
        Flying Circus mailserver role with web UI.
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

      mailHost = mkOption {
        type = types.str;
        default = defaultFQDN;
        description = ''
          FQDN of the mail server's frontend address. IP adresses and
          forward/reverse DNS must match exactly.
        '';
        example = "mail.example.com";
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

      rootAlias = mkOption {
        type = types.str;
        description = "Address to receive all mail to root@localhost.";
        default = "admin@flyingcircus.io";
      };

      smtpBind4 = mkOption {
        type = types.str;
        description = "IPv4 address for outgoing connections";
        default =
          if listenFe4 != [] then lib.head listenFe4 else "";
      };

      smtpBind6 = mkOption {
        type = types.str;
        description = "IPv6 address for outgoing connections";
        default =
          if listenFe6 != [] then lib.head listenFe6 else "";
      };

      passwdFile = mkOption {
        type = types.str;
        description = "Virtual mail user passwd file (shared Postfix/Dovecot)";
        default = "/var/lib/dovecot/passwd";
      };
    };
  };

  config = lib.mkIf role.enable {
    flyingcircus.services.mail.enable = true;
    flyingcircus.services.nginx.enable = true;
    flyingcircus.services.redis.enable = lib.mkForce true;
  };

  # see nixos/services/mail/ for further config
}
