# Declarative config.txt generation for Raspberry Pi
# Based on nixos-raspberrypi
{ lib, config, ... }:
let
  cfg = config.hardware.raspberry-pi;

  render-raspberrypi-config =
    let
      render-kvs =
        kvs:
        let
          render-kv = k: v: if v.value == null then k else "${k}=${toString v.value}";
        in
        lib.attrsets.mapAttrsToList render-kv (lib.filterAttrs (_: v: v.enable) kvs);

      render-dt-param = x: "dtparam=" + x;
      render-dt-params = params: lib.strings.concatMapStringsSep "\n" render-dt-param (render-kvs params);

      render-dt-overlay =
        { overlay, params }:
        lib.concatStringsSep "\n" (
          lib.filter (x: x != "") [
            ("dtoverlay=" + overlay)
            (render-dt-params params)
            "dtoverlay="
          ]
        );

      render-options = opts: lib.strings.concatStringsSep "\n" (render-kvs opts);

      render-dt-overlays =
        overlays:
        lib.strings.concatMapStringsSep "\n" render-dt-overlay (
          lib.attrsets.mapAttrsToList (overlay: params: {
            inherit overlay;
            inherit (params) params;
          }) (lib.filterAttrs (_: v: v.enable) overlays)
        );

      render-config-section =
        conditionalFilter:
        {
          options,
          base-dt-params,
          dt-overlays,
        }:
        let
          all-config = lib.concatStringsSep "\n" (
            lib.filter (x: x != "") [
              (render-options options)
              (render-dt-params base-dt-params)
              (render-dt-overlays dt-overlays)
            ]
          );
        in
        ''
          [${conditionalFilter}]
          ${all-config}
        '';
    in
    conf:
    lib.strings.concatStringsSep "\n" (
      (lib.attrsets.mapAttrsToList render-config-section conf) ++ [ cfg.config-extra ]
    );

in
{
  options.hardware.raspberry-pi = {
    config =
      let
        rpi-config-param = {
          options = {
            enable = lib.mkEnableOption "this config option";
            value = lib.mkOption {
              type =
                with lib.types;
                oneOf [
                  int
                  str
                  bool
                ];
            };
          };
        };

        dt-param = {
          options = {
            enable = lib.mkEnableOption "this dtparam";
            value = lib.mkOption {
              type =
                with lib.types;
                nullOr (oneOf [
                  int
                  str
                  bool
                ]);
              default = null;
            };
          };
        };

        dt-overlay = {
          options = {
            enable = lib.mkEnableOption "this overlay";
            params = lib.mkOption {
              type = with lib.types; attrsOf (submodule dt-param);
              default = { };
            };
          };
        };

        raspberry-pi-config-options = {
          options = {
            options = lib.mkOption {
              type = with lib.types; attrsOf (submodule rpi-config-param);
              default = { };
            };
            base-dt-params = lib.mkOption {
              type = with lib.types; attrsOf (submodule dt-param);
              default = { };
            };
            dt-overlays = lib.mkOption {
              type = with lib.types; attrsOf (submodule dt-overlay);
              default = { };
            };
          };
        };
      in
      lib.mkOption {
        type = with lib.types; attrsOf (submodule raspberry-pi-config-options);
        default = { };
        description = "Declarative config.txt. Keys are conditional filters: all, pi4, pi5, etc.";
      };

    config-extra = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra lines appended to config.txt.";
    };

    config-output = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Generated config.txt content.";
    };
  };

  config = {
    hardware.raspberry-pi.config-output = render-raspberrypi-config cfg.config;
  };
}
