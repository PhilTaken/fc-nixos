{ lib, stdenv, fetchurl, makeWrapper, php }:

let
  versions = {
    matomo = {
      version = "4.14.2";
      sha256 = "sha256-jPs/4bgt7VqeSoeLnwHr+FI426hAhwiP8RciQDNwCpo=";
    };

    matomo-beta = {
      version = "4.14.2";
      # `beta` examples: "b1", "rc1", null
      # when updating: use null if stable version is >= latest beta or release candidate
      beta = null;
      sha256 = "sha256-jPs/4bgt7VqeSoeLnwHr+FI426hAhwiP8RciQDNwCpo=";
    };
  };
  common = pname: { version, sha256, beta ? null }:
    let
      fullVersion = version + lib.optionalString (beta != null) "-${toString beta}";
      name = "${pname}-${fullVersion}";
    in

      stdenv.mkDerivation rec {
        inherit name;
        version = fullVersion;

        src = fetchurl {
          url = "https://builds.matomo.org/matomo-${version}.tar.gz";
          inherit sha256;
        };

        nativeBuildInputs = [ makeWrapper ];

        # make-localhost-default-database-server.patch:
        #   This changes the default value of the database server field
        #   from 127.0.0.1 to localhost.
        #   unix socket authentication only works with localhost,
        #   but password-based SQL authentication works with both.
        # TODO: is upstream interested in this?
        # -> discussion at https://github.com/matomo-org/matomo/issues/12646
        patches = [
          ./make-localhost-default-database-host.patch
        ];

        # TODO: future versions might rename the PIWIK_… variables to MATOMO_…
        # TODO: Move more unnecessary files from share/, especially using PIWIK_INCLUDE_PATH.
        #       See https://forum.matomo.org/t/bootstrap-php/5926/10 and
        #       https://github.com/matomo-org/matomo/issues/11654#issuecomment-297730843
        installPhase = ''
          runHook preInstall

          # copy everything to share/, used as webroot folder, and then remove what's known to be not needed
          mkdir -p $out/share
          cp -ra * $out/share/
          rmdir $out/share/tmp

          runHook postInstall
        '';

        filesToFix = [
          "misc/composer/build-xhprof.sh"
          "misc/composer/clean-xhprof.sh"
          "misc/cron/archive.sh"
          "plugins/GeoIp2/config/config.php"
          "plugins/TagManager/config/config.php"
          "plugins/Installation/FormDatabaseSetup.php"
          "vendor/pear/archive_tar/sync-php4"
          "vendor/szymach/c-pchart/coverage.sh"
          "vendor/matomo/matomo-php-tracker/run_tests.sh"
          "vendor/twig/twig/drupal_test.sh"
        ];

        # This fixes the consistency check in the admin interface
        #
        # The filesToFix list may contain files that are exclusive to only one of the versions we build
        # make sure to test for existence to avoid erroring on an incompatible version and failing
        postFixup = ''
          pushd $out/share > /dev/null
          for f in $filesToFix; do
            if [ -f "$f" ]; then
              length="$(wc -c "$f" | cut -d' ' -f1)"
              hash="$(md5sum "$f" | cut -d' ' -f1)"
              sed -i "s:\\(\"$f\"[^(]*(\\).*:\\1\"$length\", \"$hash\"),:g" config/manifest.inc.php
            else
              echo "INFO(files-to-fix): $f does not exist in this version"
            fi
          done
          popd > /dev/null
        '';

        meta = with lib; {
          description = "A real-time web analytics application";
          license = licenses.gpl3Plus;
          homepage = "https://matomo.org/";
          platforms = platforms.all;
        };
      };
in
lib.mapAttrs common versions
