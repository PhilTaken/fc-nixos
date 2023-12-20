{ images, pkgs }: let
  inherit (pkgs) lib;
  rawOpts = lib.optionAttrSetToDocList images.fc-options.options;

  substSpecial = x:
    if lib.isDerivation x then { _type = "derivation"; name = x.name; }
    else if builtins.isAttrs x then lib.mapAttrs (name: substSpecial) x
    else if builtins.isList x then map substSpecial x
    else if lib.isFunction x then "<function>"
    else x;

  filteredOpts = lib.filter (opt: opt.visible && !opt.internal) rawOpts;
  optionsList = lib.flip map filteredOpts
    (opt: opt
      // lib.optionalAttrs (opt ? example) { example = substSpecial opt.example; }
      // lib.optionalAttrs (opt ? default) { default = substSpecial opt.default; }
      // lib.optionalAttrs (opt ? type) { type = substSpecial opt.type; }
    );

  optionsNix = builtins.listToAttrs (map (o: { name = o.name; value = removeAttrs o ["name" "visible" "internal"]; }) optionsList);
  finalOptions = lib.mapAttrsToList (name: option: option // { inherit name; }) optionsNix;
in lib.hydraJob (pkgs.writeText "options.json" (builtins.unsafeDiscardStringContext (builtins.toJSON finalOptions)))
