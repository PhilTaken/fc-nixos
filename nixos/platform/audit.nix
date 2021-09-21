{ config, lib, pkgs, ... }:

with lib;

# audit-related configuration

let
  auditUserspace = pkgs.fetchFromGitHub {
    owner = "linux-audit";
    repo = "audit-userspace";
    rev = "6b09724c69d91668418ddb3af00da6db6755208c";
    sha256 = "1muskUu3Z8SrtrhWiFUh5MeMi4da5on3mV3/TkF8Qbw=";
    fetchSubmodules = false;
  };
in
{
  /* XXX after beta
    imports = [
      (mkRemovedOptionModule [ "flyingcircus" "audit" "enable" ] "Auditing is now enabled by default, this option can be safely removed")
    ];
  */

  options.flyingcircus.audit = {
    enable = mkEnableOption "auditing (beta)";
  };

  config = (mkIf (config.flyingcircus.audit.enable) (
    mkMerge [
      {
        # Enable audit
        security.audit = {
          enable = true; # audit system
          # list see https://github.com/linux-audit/audit-userspace/tree/master/rules
          /* rules = map (rule: replaceStrings [ "'" ] [ "" ] (builtins.readFile "${auditUserspace}/rules/${rule}"))
            [ "30-pci-dss-v31.rules" ]; */
          rules = [
            "-a exit,always -F arch=b64 -F euid=0 -S execve"
            "-a exit,always -F arch=b32 -F euid=0 -S execve"
          ];
        };
      }

      (mkIf (config.system.nixos.release != "21.11") (let
        # we can also modify pam itself, but this causes massive rebuilds
        pamWithAudit = pkgs.pam.overrideAttrs(a: a // { buildInputs = a.buildInputs ++ [ pkgs.libaudit ]; });
        pamAppend = name: extra: {
          source = lib.mkForce (pkgs.writeText "${name}.pam"
            (
              let
                replaced = replaceStrings [ "# Session management." ] [ "# Session management.\nsession required ${pamWithAudit}/lib/security/pam_tty_audit.so ${extra}" ] config.security.pam.services.${name}.text;
              in
              # make sure anything changed at all
              if config.security.pam.services.${name}.text != replaced then replaced
              else throw "audit replace-hack does not work anymore, please fix or use upstream version"
            )
          );
        };
      in {
        # XXX nixOS 21.11 will have proper support for pam_tty_audit, this can be removed then

        # nixOS pam module has no flag for this module
        # also not setting it as .text because pam already does source, so we need to improvise
        # plus pam_tty_audit does not get built by default as it require libaudit, so we need to hack that in aswell
        environment.etc."pam.d/login" = pamAppend "login" "enable=*\nsession required ${pamWithAudit}/lib/security/pam_loginuid.so";
        environment.etc."pam.d/sshd" = pamAppend "sshd" "enable=*\nsession required ${pamWithAudit}/lib/security/pam_loginuid.so";
        environment.etc."pam.d/sudo" = pamAppend "sudo" "enable=* open_only";
      }))

      (mkIf (config.system.nixos.release == "21.11") {
        security.pam.services = {
          login = {
            setLoginUid = true;
            ttyAudit = {
              enable = true;
              enablePattern = "*";
            };
          };
          sshd = {
            setLoginUid = true;
            ttyAudit = {
              enable = true;
              enablePattern = "*";
            };
          };
          sudo = {
            ttyAudit = {
              enable = true;
              enablePattern = "*";
              openOnly = true;
            };
          };
        };
      })
    ]));
}
