{ system ? builtins.currentSystem
, nixpkgs ? (import ../../versions.nix {}).nixpkgs
, pkgs ? import ../.. { inherit nixpkgs; }
}:

with import "${nixpkgs}/nixos/lib/testing.nix" { inherit system; };
with pkgs.lib;

let
  router =
    { config, pkgs, ... }:
    with pkgs.lib;
    let
      vlanIfs = range 1 (length config.virtualisation.vlans);
    in {
      environment.systemPackages = with pkgs; [ iptables curl ];
      virtualisation.vlans = [ 1 2 3 ];  # fe srv tr
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;
      networking = {
        useDHCP = false;
        firewall.allowPing = true;
        firewall.checkReversePath = true;
        interfaces = mkForce (listToAttrs (flip map vlanIfs (n:
          nameValuePair "eth${toString n}" {
            ipv4.addresses = [
              { address = "10.51.${toString n}.1"; prefixLength = 24; }
            ];
            ipv6.addresses = [
              { address = "2001:db8:${toString n}::1"; prefixLength = 64; }
            ];
          })));
      };

    };

  encInterfaces = id: {
    fe = {  # VLAN 1
      mac = "52:54:00:12:01:0${id}";
      networks = {
        "10.51.1.0/24" = [ "10.51.1.1${id}" "10.51.1.2${id}" ];
        "2001:db8:1::/64" = [ "2001:db8:1::1${id}" "2001:db8:1::2${id}" ];
      };
      gateways = {
        "10.51.1.0/24" = "10.51.1.1";
        "2001:db8::/64" = "2001:db8:1::1";
      };
    };
    srv = {  # VLAN 2
      mac = "52:54:00:12:02:0${id}";
      networks = {
        "10.52.2.0/24" = [ "10.51.2.1${id}" "10.51.2.2${id}" ];
        "2001:db8:2::/64" = [ "2001:db8:2::1${id}" "2001:db8:2::2${id}" ];
      };
      gateways = {
        "10.51.2.0/24" = "10.51.2.1";
        "2001:db8:2::/64" = "2001:db8:2::1";
      };
    };
  };

  testCases = {

    loopback = {
      name = "loopback";
      machine.imports = [ ../../nixos ];
      testScript = ''
        $machine->waitForUnit("network.target");
        $machine->succeed("ip addr show lo | grep -q 'inet 127.0.0.1/8 '");
        $machine->succeed("ip addr show lo | grep -q 'inet6 ::1/128 '");
      '';
    };

    ping-vlans = {
      name = "ping-vlans";
      nodes.client =
        { pkgs, ... }:
        {
          imports = [ ../../nixos ];
          virtualisation.vlans = [ 1 2 ];
          flyingcircus.enc.parameters.interfaces = encInterfaces "1";
        };
      nodes.router = router;
      testScript = ''
        startAll;
        $client->waitForUnit("network-online.target");
        $router->waitForUnit("network-online.target");

        print("\n* Router network overview\n");
        print($router->succeed("ip a"));
        print("\n* Client network overview\n");
        print($client->succeed("ip a"));
        # ipv6 needs more time, wait until self-ping works
        $router->waitUntilSucceeds("ping -c1 2001:db8:1::1");
        $client->waitUntilSucceeds("ping -c1 2001:db8:1::11");

        subtest "ping fe", sub {
          $client->succeed("ping -I ethfe -c1 10.51.1.1");
          $client->succeed("ping -I ethfe -c1 2001:db8:1::1");
          $router->succeed("ping -c1 10.51.1.11");
          $router->succeed("ping -c1 10.51.1.21");
          $router->succeed("ping -c1 2001:db8:1::11");
          $router->succeed("ping -c1 2001:db8:1::21");
        };

        subtest "ping srv", sub {
          $client->succeed("ping -I ethsrv -c1 10.51.2.1");
          $client->succeed("ping -I ethsrv -c1 2001:db8:2::1");
          $router->succeed("ping -c1 10.51.2.11");
          $router->succeed("ping -c1 10.51.2.21");
          $router->succeed("ping -c1 2001:db8:2::11");
          $router->succeed("ping -c1 2001:db8:2::21");
        };

        subtest "ping default gateway", sub {
          $client->succeed("ping -c1 10.51.3.1");
          $client->succeed("ping -c1 2001:db8:3::1");
        };
      '';
    };

    firewall =
      let
        firewalledServer =
          { hostId, localConfigPath ? "/etc/local" } :
          {
            imports = [ ../../nixos ];
            virtualisation.vlans = [ 1 2 ];
            flyingcircus.infrastructureModule = "flyingcircus";
            flyingcircus.enc.parameters.interfaces = encInterfaces hostId;
            flyingcircus.localConfigPath = localConfigPath;
            services.nginx.enable = true;
            services.nginx.virtualHosts."srv${hostId}" = { root = ./.; };
            users.users.s-test = {
              isNormalUser = true;
              extraGroups = [ "service" ];
            };
          };
      in {
        name = "firewall";
        # encInterfaces defines MAC addresses for the first node
        nodes.router = router;
        nodes.srv2 = firewalledServer { hostId = "2"; };
        nodes.srv3 = firewalledServer {
          hostId = "3";
          localConfigPath = ./open-fe-80;
        };
        testScript = ''
          startAll;
          $router->waitForUnit("network-online.target");

          $srv2->waitForUnit("nginx.service");
          subtest "default firewall", sub {
            $router->fail("curl http://10.51.1.12/default.nix");
            $router->fail("curl http://[2001:db8:1::12]/default.nix");
            $router->fail("curl http://10.51.2.12/default.nix");
            $router->fail("curl http://[2001:db8:2::12]/default.nix");
          };

          $srv3->waitForUnit("nginx.service");
          subtest "firewall opens FE", sub {
            $router->succeed("curl http://10.51.1.13/default.nix");
            $router->succeed("curl http://[2001:db8:1::13]/default.nix");
            $router->fail("curl http://10.51.2.13/default.nix");
            $router->fail("curl http://[2001:db8:2::13]/default.nix");
          };

          # service user should be able to write to its local config dir
          $srv2->succeed('sudo -u s-test touch /etc/local/firewall/test');
        '';
      };

  };

in
mapAttrs (const (attrs: makeTest (attrs // {
  name = "network-${attrs.name}";
}))) testCases
