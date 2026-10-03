# pi-nix

Nix package and home-manager module for [pi.dev](https://pi.dev) coding agent.

![pi--v1.0.1](https://img.shields.io/badge/pi--v1.0.1-blue)

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
    secret = "your-api-key";
    # env = { BASE_URL = "https://example.com"; };
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
| `auth` | attrsOf | `{}` | Auth credentials per provider (`secret` = API key/env var/`!cmd`, optional `env`; unknown fields pass through, e.g. OAuth `refresh`/`access`/`expires`) |
| `customProviders` | attrsOf | `{}` | Custom providers (models.json; unknown fields pass through, e.g. `headers`, `compat`, `modelOverrides`) |
| `packages` | listOf (str \| { source; autoload?; extensions?; skills?; prompts?; themes? }) | `[]` | npm/git package specifiers, optionally with resource filtering |
| `extensions` | listOf str | `[]` | Local extension file paths or directories |
| `skills` | listOf str | `[]` | Local skill file paths or directories |
| `prompts` | listOf str | `[]` | Local prompt template paths or directories |
| `themes` | listOf str | `[]` | Local theme file paths or directories |
| `defaultThinkingLevel` | null/enum | `null` | `"off"`\|`"minimal"`\|`"low"`\|`"medium"`\|`"high"`\|`"xhigh"`\|`"max"` |
| `transport` | null/enum | `null` | `"auto"`\|`"sse"`\|`"websocket"`\|`"websocket-cached"` |
| `modelThinkingLevels` | attrsOf enum | `{}` | Per-model thinking level keyed by `"provider/modelId"` |
| `steeringMode` | null/enum | `null` | `"all"`\|`"one-at-a-time"` (queued message application) |
| `followUpMode` | null/enum | `null` | `"all"`\|`"one-at-a-time"` (follow-up application) |
| `compaction` | null/attrs | `null` | Compaction: `enabled`, `reserveTokens`, `keepRecentTokens`, `modelOverrides."provider/model".{reserveTokens,keepRecentTokens}` |
| `branchSummary` | null/attrs | `null` | Branch summaries: `reserveTokens`, `skipPrompt` |
| `retry` | null/attrs | `null` | Retries: `enabled`, `maxRetries`, `baseDelayMs`, `maxAgentDelayMs`, `provider.{timeoutMs,maxRetries,maxRetryDelayMs}` |
| `hideThinkingBlock` | null/bool | `null` | Hide thinking blocks in transcript |
| `showCacheMissNotices` | null/bool | `null` | Show cache miss notices |
| `externalEditor` | null/str | `null` | Editor command for Ctrl+G (null = `$VISUAL`/`$EDITOR` detection) |
| `shellPath` | null/str | `null` | Shell used by the bash tool (null = platform default) |
| `quietStartup` | null/bool | `null` | Suppress startup banner |
| `defaultProjectTrust` | null/enum | `null` | `"ask"`\|`"always"`\|`"never"` (global-only) |
| `shellCommandPrefix` | null/str | `null` | Prefix prepended to every bash command |
| `npmCommand` | listOf str | `[]` | npm command as argv (empty = `npm`) |
| `collapseChangelog` | null/bool | `null` | Collapse changelog entries |
| `enableInstallTelemetry` | null/bool | `null` | Anonymous install telemetry |
| `enableAnalytics` | null/bool | `null` | Anonymous usage analytics |
| `trackingId` | null/str | `null` | Analytics id (pi generates one; set only to pin) |
| `lastChangelogVersion` | null/str | `null` | Internal changelog marker (pi manages; set only to pin) |
| `enableSkillCommands` | null/bool | `null` | Expose skills as slash commands |
| `terminal` | null/attrs | `null` | Terminal: `showImages`, `imageWidthCells`, `clearOnShrink`, `showTerminalProgress`, `hyperlinks` (bool\|`"auto"`), `images` (`"kitty"`\|`"iterm2"`\|`"auto"`\|false), `trueColor` (bool\|`"auto"`) |
| `images` | null/attrs | `null` | Image input: `autoResize`, `blockImages` |
| `enabledModels` | listOf str | `[]` | Model cycling patterns (empty = all available models) |
| `defaultTools` | listOf str | `[]` | Enabled tool ids (empty = full built-in set) |
| `doubleEscapeAction` | null/enum | `null` | `"fork"`\|`"tree"`\|`"none"` |
| `treeFilterMode` | null/enum | `null` | `"default"`\|`"no-tools"`\|`"user-only"`\|`"labeled-only"`\|`"all"` |
| `thinkingBudgets` | null/attrs | `null` | Token budgets: `minimal`, `low`, `medium`, `high` |
| `editorPaddingX` | null/int | `null` | Editor horizontal padding (0-3) |
| `outputPad` | null/enum | `null` | `0`\|`1` (blank line after output blocks) |
| `autocompleteMaxVisible` | null/int | `null` | Max autocomplete rows (3-20) |
| `showHardwareCursor` | null/bool | `null` | Use hardware cursor |
| `markdown` | null/attrs | `null` | Markdown: `codeBlockIndent`, `mermaid` (`"off"`\|`"final"`\|`"streaming"`) |
| `warnings` | null/attrs | `null` | Warnings: `anthropicExtraUsage` |
| `sessionDir` | null/str | `null` | Session storage dir (overridden by `PI_CODING_AGENT_SESSION_DIR`/`--session-dir`) |
| `httpProxy` | null/str | `null` | Proxy URL fed to `HTTP_PROXY`/`HTTPS_PROXY` (global-only) |
| `httpIdleTimeoutMs` | null/int | `null` | HTTP idle timeout; 0 disables (null = 300000) |
| `cacheWarming` | null/enum | `null` | `"off"`\|`"streaming"`\|`"idle"` (global-only; null = `"streaming"`) |
| `websocketConnectTimeoutMs` | null/int | `null` | WS connect timeout; 0 disables (null = 15000) |
| `tuiMode` | null/enum | `null` | `"regular"`\|`"fullscreen"` |
| `fullscreenExitOutput` | null/enum | `null` | `"transcript"`\|`"resume-hint"` |
| `fullscreenScrollbar` | null/enum | `null` | `"hidden"`\|`"auto"`\|`"always"` |
| `fullscreenCopyOnSelect` | null/bool | `null` | Copy selection immediately in fullscreen |
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
