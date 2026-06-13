# pi-nix

Nix package and home-manager module for [pi.dev](https://pi.dev) coding agent.

![pi--v0.79.3](https://img.shields.io/badge/pi--v0.79.3-blue)

## What this does

- **Packages pi as a single binary** via `bun build --compile` (no node needed at runtime)
- **Home-manager module** for declarative configuration (settings, auth, providers, extensions)
- **Auto-updates** via GitHub Actions checking npm every 6h

## Quick start

```bash
nix run github:vabatta/pi-nix
```

## Flake usage

```nix
# flake.nix
{
  inputs.pi-nix.url = "github:vabatta/pi-nix";
  inputs.pi-nix.inputs.nixpkgs.follows = "nixpkgs";
}

# In home-manager config:
home-manager.users.<user>.imports = [
  inputs.pi-nix.homeManagerModules.default
];
```

### Configuration

```nix
programs.pi = {
  enable = true;
  package = inputs.pi-nix.packages.${system}.default;
  provider = "openrouter";
  model = "nvidia/nemotron-3-nano-30b-a3b:free";
  theme = "dark";

  auth.openrouter = {
    type = "api_key";
    key = "your-api-key";
  };

  packages = [
    "npm:pi-mcp-adapter"
    "npm:pi-subagents"
    # Object form filters which resources to load from a package:
    { source = "npm:pi-web-access"; skills = [ "fetch" ]; }
  ];

  # Local (non-package) resources:
  skills = [ "/etc/pi/skills" ];

  defaultThinkingLevel = "medium";
  transport = "auto";

  customProviders.ollama-local = {
    name = "Ollama (local)";
    baseUrl = "http://localhost:11434/v1";
    apiKey = "ollama";
    models = [
      { id = "gemma4:26b"; name = "Gemma 4 26B"; input = ["text" "image"]; }
    ];
  };

  mutableSettings = true;
  preLaunchHook = ""; # shell commands before pi launches
};
```

## Updating

```bash
nix flake update pi-nix   # in your dotfiles
darwin-rebuild switch       # or home-manager switch
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable pi |
| `package` | package | (required) | The pi package |
| `nodejs` | package | `pkgs.nodejs` | Node.js for extension management |
| `provider` | enum/str | `"openrouter"` | Default provider |
| `model` | str | `""` | Default model |
| `theme` | null/str | `null` | Theme name (null = auto-detect) |
| `auth` | attrsOf | `{}` | Auth credentials per provider |
| `customProviders` | attrsOf | `{}` | Custom providers (models.json) |
| `packages` | listOf (str \| { source; extensions?; skills?; prompts?; themes? }) | `[]` | npm/git package specifiers, optionally with resource filtering |
| `extensions` | listOf str | `[]` | Local extension file paths or directories |
| `skills` | listOf str | `[]` | Local skill file paths or directories |
| `prompts` | listOf str | `[]` | Local prompt template paths or directories |
| `themes` | listOf str | `[]` | Local theme file paths or directories |
| `defaultThinkingLevel` | null/enum | `null` | `"off"`\|`"minimal"`\|`"low"`\|`"medium"`\|`"high"`\|`"xhigh"` |
| `transport` | null/enum | `null` | `"auto"`\|`"sse"`\|`"websocket"`\|`"websocket-cached"` |
| `mutableSettings` | bool | `true` | Seed-once vs overwrite |
| `settings` | attrs | `{}` | Extra settings.json keys (escape hatch for any field not typed above) |
| `preLaunchHook` | lines | `""` | Pre-launch shell hook |

## Architecture

- **Binary**: Built from source via `bun build --compile` — single executable, no node runtime needed
- **Dependencies**: FOD (fixed-output derivation) for `node_modules` — bypasses `buildNpmPackage` hash issues
- **Extensions**: Managed by pi at runtime via npm (`pi install npm:...`)
- **Config**: `settings.json` seeded by nix, mutable at runtime via `/settings`
- **Auth/Models**: Immutable nix-managed symlinks

## License

MIT
