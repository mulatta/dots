{ pkgs, ... }:
{
  language-server = {
    # JSON Language Server with schema support
    vscode-json-language-server = {
      command = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
      args = [ "--stdio" ];
      config = {
        json = {
          validate = {
            enable = true;
          };
          format = {
            enable = true;
          };
          schemas = [
            {
              fileMatch = [ "package.json" ];
              url = "https://json.schemastore.org/package.json";
            }
            {
              fileMatch = [
                "tsconfig.json"
                "tsconfig.*.json"
              ];
              url = "https://json.schemastore.org/tsconfig.json";
            }
            {
              fileMatch = [
                ".prettierrc"
                ".prettierrc.json"
              ];
              url = "https://json.schemastore.org/prettierrc.json";
            }
            {
              fileMatch = [
                ".eslintrc"
                ".eslintrc.json"
              ];
              url = "https://json.schemastore.org/eslintrc.json";
            }
            {
              fileMatch = [ "composer.json" ];
              url = "https://json.schemastore.org/composer.json";
            }
          ];
        };
        provideFormatter = false; # Use prettier for formatting
      };
    };

    # Python language server with enhanced linting
    ruff = {
      command = "${pkgs.ruff}/bin/ruff";
      args = [ "server" ];
      config.settings = {
        lineLength = 88; # Black style line length
        lint.select = [
          "E4" # Import errors
          "E7" # Statement errors
          "F" # Pyflakes errors
          "W" # Warning errors
          "I" # Import sorting
          "N" # Naming conventions
        ];
        lint.ignore = [ "E501" ]; # Line too long (handled by formatter)
        format.preview = true;
      };
    };

    # Python type checker
    pyright = {
      command = "${pkgs.pyright}/bin/pyright-langserver";
      args = [ "--stdio" ];
      config = {
        python = {
          analysis = {
            typeCheckingMode = "basic";
            autoSearchPaths = true;
            useLibraryCodeForTypes = true;
          };
        };
      };
    };

    # Rust language server with enhanced configuration
    rust-analyzer = {
      command = "${pkgs.rust-analyzer}/bin/rust-analyzer";
      config = {
        check = {
          command = "clippy"; # Use clippy for better linting
        };
        # Enhanced inlay hints for better code readability
        inlayHints = {
          bindingModeHints = {
            enable = false;
          };
          chainingHints = {
            enable = true;
          };
          closingBraceHints = {
            enable = true;
            minLines = 25;
          };
          closureReturnTypeHints = {
            enable = "never";
          };
          lifetimeElisionHints = {
            enable = "never";
            useParameterNames = false;
          };
          maxLength = 25;
          parameterHints = {
            enable = true;
          };
          reborrowHints = {
            enable = "never";
          };
          renderColons = true;
          typeHints = {
            enable = true;
            hideClosureInitialization = false;
            hideNamedConstructor = false;
          };
        };
      };
    };

    # Modern Nix language server with comprehensive support
    nixd = {
      command = "${pkgs.nixd}/bin/nixd";
      config = {
        nixpkgs = {
          expr = "import <nixpkgs> { }";
        };
        options = {
          nixos = {
            expr = "import <nixpkgs/nixos> { }";
          };
          home_manager = {
            expr = "import <home-manager/modules> { }";
          };
        };
      };
    };

    # Legacy Nix language server (backup)
    nil = {
      command = "${pkgs.nil}/bin/nil";
      config = {
        formatting = {
          command = [ "${pkgs.alejandra}/bin/alejandra" ];
        };
      };
    };

    # TOML language server
    taplo = {
      command = "${pkgs.taplo}/bin/taplo";
      args = [
        "lsp"
        "stdio"
      ];
    };

    # Markdown language server
    marksman = {
      command = "${pkgs.marksman}/bin/marksman";
      args = [ "server" ];
    };

    # Typst language server
    tinymist = {
      command = "${pkgs.tinymist}/bin/tinymist";
    };

    # YAML language server with schema support
    yaml-language-server = {
      command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
      args = [ "--stdio" ];
      config = {
        yaml = {
          keyOrdering = false;
          format = {
            enable = true;
          };
          validate = true;
          schemaStore = {
            enable = true;
            url = "https://www.schemastore.org/api/json/catalog.json";
          };
        };
      };
    };

    # Bash language server
    bash-language-server = {
      command = "${pkgs.bash-language-server}/bin/bash-language-server";
      args = [ "start" ];
    };
  };

  language = [
    # JSON with schema validation
    {
      name = "json";
      scope = "source.json";
      injection-regex = "json";
      file-types = [ "json" ];
      language-servers = [ "vscode-json-language-server" ];
      formatter = {
        command = "${pkgs.nodePackages.prettier}/bin/prettier";
        args = [
          "--parser"
          "json"
        ];
      };
      auto-format = true;
    }

    # JSON with Comments support
    {
      name = "jsonc";
      scope = "source.json";
      injection-regex = "jsonc";
      file-types = [ "jsonc" ];
      language-servers = [ "vscode-json-language-server" ];
      formatter = {
        command = "${pkgs.nodePackages.prettier}/bin/prettier";
        args = [
          "--parser"
          "json"
        ];
      };
      auto-format = true;
    }

    # Python with dual LSP support (ruff + pyright)
    {
      name = "python";
      scope = "source.python";
      injection-regex = "python";
      file-types = [
        "py"
        "pyi"
      ];
      shebangs = [
        "python"
        "python3"
      ];
      roots = [
        "pyproject.toml"
        "setup.py"
        "setup.cfg"
        "Poetry.lock"
        "requirements.txt"
        "Pipfile"
        ".python-version"
      ];
      language-servers = [
        "ruff" # Fast linting and formatting
        "pyright" # Type checking
      ];
      formatter = {
        command = "${pkgs.ruff}/bin/ruff";
        args = [
          "format"
          "--stdin-filename"
          "file.py"
          "-"
        ];
      };
      auto-format = true;
    }

    # Rust with clippy integration
    {
      name = "rust";
      scope = "source.rust";
      file-types = [ "rs" ];
      roots = [
        "Cargo.toml"
        "Cargo.lock"
      ];
      language-servers = [ "rust-analyzer" ];
      formatter = {
        command = "${pkgs.rustfmt}/bin/rustfmt";
        args = [
          "--edition"
          "2021"
        ];
      };
      auto-format = true;
    }

    # Nix with dual LSP support
    {
      name = "nix";
      scope = "source.nix";
      file-types = [ "nix" ];
      roots = [
        "flake.nix"
        "shell.nix"
        "default.nix"
      ];
      language-servers = [
        "nixd" # Primary modern LSP
        "nil" # Backup legacy LSP
      ];
      formatter = {
        command = "${pkgs.alejandra}/bin/alejandra";
        args = [ "--quiet" ];
      };
      auto-format = true;
    }

    # TOML configuration files
    {
      name = "toml";
      scope = "source.toml";
      file-types = [ "toml" ];
      language-servers = [ "taplo" ];
      formatter = {
        command = "${pkgs.taplo}/bin/taplo";
        args = [
          "format"
          "-"
        ];
      };
      auto-format = true;
    }

    # Markdown documentation
    {
      name = "markdown";
      scope = "text.markdown";
      file-types = [
        "md"
        "markdown"
      ];
      language-servers = [ "marksman" ];
      formatter = {
        command = "${pkgs.nodePackages.prettier}/bin/prettier";
        args = [
          "--parser"
          "markdown"
        ];
      };
      auto-format = true;
    }

    # Typst document preparation
    {
      name = "typst";
      scope = "source.typst";
      file-types = [ "typ" ];
      language-servers = [ "tinymist" ];
      formatter = {
        command = "${pkgs.typstyle}/bin/typstyle";
        args = [
          "-l"
          "50"
          "-t"
          "4"
        ];
      };
      auto-format = true;
    }

    # YAML configuration files with schema support
    {
      name = "yaml";
      scope = "source.yaml";
      file-types = [
        "yml"
        "yaml"
      ];
      language-servers = [ "yaml-language-server" ];
      formatter = {
        command = "${pkgs.nodePackages.prettier}/bin/prettier";
        args = [
          "--parser"
          "yaml"
        ];
      };
      auto-format = true;
    }

    # Shell scripts with formatting support
    {
      name = "bash";
      scope = "source.bash";
      file-types = [
        "sh"
        "bash"
      ];
      shebangs = [
        "sh"
        "bash"
      ];
      language-servers = [ "bash-language-server" ];
      formatter = {
        command = "${pkgs.shfmt}/bin/shfmt";
        args = [
          "-i"
          "2"
          "-ci"
        ]; # 2 spaces indent, case indent
      };
      auto-format = true;
    }
  ];

  # Tree-sitter grammars for syntax highlighting
  grammars = [
    {
      name = "python";
      source = {
        git = "https://github.com/tree-sitter/tree-sitter-python";
        rev = "4bfdd9033a2225cc95032ce77066b7aeca9e2efc";
      };
    }
    {
      name = "json";
      source = {
        git = "https://github.com/tree-sitter/tree-sitter-json";
        rev = "73076754005a460947cafe8e03a8cf5fa4fa2938";
      };
    }
    {
      name = "yaml";
      source = {
        git = "https://github.com/tree-sitter/tree-sitter-yaml";
        rev = "0e36bed171768908f331ff7dff9d956bae016efb";
      };
    }
    {
      name = "bash";
      source = {
        git = "https://github.com/tree-sitter/tree-sitter-bash";
        rev = "275effdfc0edce774acf7d481f9ea195c6c403cd";
      };
    }
  ];
}
