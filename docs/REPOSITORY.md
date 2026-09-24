# Repository structure

One Git repository owns the native product, website, documentation, and historical studies. There is no application dependency on the website or the studies.

| Path | Owns |
| --- | --- |
| `macos/Tabnax/` | App lifecycle, keyboard routing, catalogues, focus, settings, native rendering. |
| `macos/Packages/TabnaxCore/` | Pure Swift settings, labels, selection/navigation, theme/layout models. |
| `macos/BrowserCompanion/` | Firefox/Zen extension, installation guide, protocol tests. |
| `macos/SafariCompanion/` | Embedded Safari extension and native handler. |
| `macos/TabnaxTests/`, `macos/TabnaxUITests/`, `macos/Fixtures/` | Native contracts, UI tests, controlled fixture windows. |
| `website/` | Deployable static homepage, guide, demo, public assets. |
| `docs/` | Current product and contributor guidance. |
| `design-exploration/`, `settings-exploration/` | Historical editable prototypes and their contracts. |
| `scripts/` | Shared checks, secret audit, verified scanner installer. |
| `.github/` | CI, dependency updates, issue and PR templates. |

## Decisions

- Keep `macos/` in place: Xcode, build scripts, local development app paths, and established workflows already use it. An extra `apps/` wrapper would add churn without creating a useful boundary.
- Move the homepage and all assets into `website/`: hosting this directory cannot accidentally expose `.git`, native source, or local build output. A standalone HTML guide replaces source links outside the website.
- Keep the named exploration directories: they contain linked historical studies and runnable standalone artifacts. Their READMEs explicitly mark them as historical.
- Keep current product and technical documentation in `docs/`. Competitor research, launch planning, campaign assets, and outreach records are outside this repository.
- Publish only reviewed native sample renders in `website/assets/native/`. Raw logs, browser snapshots, machine captures, result bundles, and build products remain ignored on disk.
- Keep the repo free of production signing identities and credentials. Ad-hoc signing is the shared development default; local signing config is ignored.

## Adding files

Keep component-specific docs beside their code. Place shared product/architecture guidance in `docs/`. Add public images only after reviewing visible data and metadata, then document provenance in `website/README.md`.

Generated native artifacts belong in `macos/build/`; browser automation output belongs in `output/` or an existing ignored verification directory. Do not force-add generated evidence to make a documentation link work. Record the result in Markdown and label raw evidence as local.

Documentation must remain useful to someone with only a public checkout. Keep required technical rationale here and link only to included files or public resources.
