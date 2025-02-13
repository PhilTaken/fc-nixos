{ config, lib, ... }:

let
  cfg = config.flyingcircus;
  fclib = config.fclib;

in
with lib;
{
  options.flyingcircus = with types; {

    enc = mkOption {
      type = attrs;
      description = "Data from the external node classifier.";
    };

    encPath = mkOption {
      default = "/etc/nixos/enc.json";
      type = path;
      description = "Where to find the ENC json file.";
    };

    encAddresses = mkOption {
      type = listOf attrs;
      description = "List of addresses of machines in the neighbourhood.";
      example = [ {
        ip = "2a02:238:f030:1c3::104c/64";
        mac = "02:00:00:03:11:b1";
        name = "test03";
        rg = "test";
        rg_parent = "";
        ring = 1;
        vlan = "srv";
      } ];
    };

    encAddressesPath = mkOption {
      defaultText = "/etc/nixos/addresses_srv.json";
      default = /etc/nixos/addresses_srv.json;
      type = path;
      description = "Where to find the address list json file.";
    };

    systemState = mkOption {
      type = attrs;
      description = "The current system state as put out by fc-manage";
    };

    encServicesPath = mkOption {
      defaultText = "/etc/nixos/services.json";
      default = /etc/nixos/services.json;
      type = path;
      description = "Where to find the ENC services json file.";
    };

    encServiceClients = mkOption {
      type = listOf attrs;
      description = ''
        Service clients in the environment as provided by the ENC.
      '';
    };

    encServiceClientsPath = mkOption {
      defaultText = "/etc/nixos/service_clients.json";
      default = /etc/nixos/service_clients.json;
      type = path;
      description = "Where to find the ENC service clients json file.";
    };

    systemStatePath = mkOption {
      defaultText = "/etc/nixos/system_state.json";
      default = /etc/nixos/system_state.json;
      type = path;
      description = "Where to find the system state json file.";
    };

    encServices = mkOption {
      type = listOf attrs;
      description = "Services in the environment as provided by the ENC.";
    };

    active-roles = mkOption {
      default = attrByPath [ "roles" ] [] cfg.enc;
      type = types.listOf types.str;
      example = [ "generic" "webgateway" "webproxy" ];
      description = ''
        Which roles to activate.  Defaults to the roles provided by the ENC.
      '';
    };

  };

  config = {

    environment.etc = optionalAttrs
      (hasAttrByPath ["parameters" "directory_secret"] cfg.enc)
      {
        "directory.secret".text = cfg.enc.parameters.directory_secret;
        "directory.secret".mode = "0600";
      };

    flyingcircus = {
      enc =
        fclib.mkPlatform (fclib.jsonFromFile cfg.encPath "{}");
      encAddresses =
        fclib.mkPlatform (fclib.jsonFromFile cfg.encAddressesPath "[]");
      encServices =
        fclib.mkPlatform (fclib.jsonFromFile cfg.encServicesPath "[]");
      encServiceClients =
        fclib.mkPlatform (fclib.jsonFromFile cfg.encServiceClientsPath "[]");
      systemState =
        fclib.mkPlatform (fclib.jsonFromFile cfg.systemStatePath "{}");
    };

  };
}
