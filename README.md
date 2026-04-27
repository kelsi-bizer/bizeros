# BizerOS — A one-click self-hosted business platform

BizerOS is a white-label, business-focused fork of [Runtipi](https://github.com/runtipi/runtipi). It packages the apps small businesses actually run — auth, chat, files, billing, networking — behind a one-click installer and a single dashboard you control.

[![License](https://img.shields.io/github/license/kelsi-bizer/bizeros)](LICENSE)

> [!NOTE]
> BizerOS is built on top of Runtipi (TypeScript + NestJS + React). Most of the heavy lifting — Docker orchestration, the app-store model, Traefik routing — is Runtipi's work. BizerOS adds branded UI, a curated app store, and an opinionated first-boot flow.

## What ships out of the box

On first boot, BizerOS automatically:

1. Registers [github.com/kelsi-bizer/bizeros-appstore](https://github.com/kelsi-bizer/bizeros-appstore) as the default app store.
2. Installs a curated set of business-ready apps:
   - **Authentik** — SSO / identity
   - **BizerOS Dash** — the BizerOS dashboard, slug `bizeros-dash` ([source](https://github.com/kelsi-bizer/bizeros-dashboard))
   - **BizerOS Chat** — team chat, slug `bizeros-chat` ([source](https://github.com/kelsi-bizer/bizeros-chat))
   - **Miles** — the Miles agent, slug `miles` ([source](https://github.com/kelsi-bizer/miles-agent))
   - **Nextcloud** — file sync & sharing
   - **Invoice Ninja** — invoicing & billing
   - **Infisical** — secrets management

Everything else is opt-in via the standard app store browser.

## Getting started

Installation instructions follow the upstream Runtipi flow until BizerOS ships its own packaged installer. See the [Runtipi getting-started docs](https://www.runtipi.io/docs/getting-started/installation) for now; only the default app store and the curated bundle differ.

## Development

```bash
bun install
bun run start:dev   # docker-compose dev stack
bun run tsc         # type-check
bun run lint        # biome
bun test            # backend unit tests
```

## Acknowledgements

BizerOS is a fork of [Runtipi](https://github.com/runtipi/runtipi). Our deepest thanks to the Runtipi maintainers and contributors — none of this exists without their work. If BizerOS helps your business, please consider [sponsoring Runtipi](https://github.com/runtipi/runtipi?sponsor=1).

## License

GNU General Public License v3.0 — same as upstream Runtipi.
