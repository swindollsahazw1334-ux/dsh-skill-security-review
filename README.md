# dsh-skill-security-review

A DeepSeek Harness (DSH) skill bundle: **review a third-party plugin for security before installing it**, with evidence instead of vibes.

This is a skill, not an access-control layer. It gives the agent a fixed procedure for "audit this package": fetch metadata → unpack and statically scan → human review → A/B/C verdict → optional quarantine dry-run.

## Install

```bash
dsh plugin --profile desktop add dsh-skill-security-review
```

Restart DSH; the `plugin-security-review` skill appears in the skill catalog.

## What it does

1. **Metadata** — publisher, first publish date, release cadence, whether the repo matches the npm scope, `engines.dsh` compatibility.
2. **Static scan** (`scripts/audit.ps1`, only `npm pack` into a temp dir, never installs):
   install hooks, `child_process`, `eval`/`vm`, outbound hosts, upload-style calls, credential paths (`~/.dsh`, `~/.ssh`, …), base64/obfuscation signals, dependency tree.
3. **Human review** — the script reports locations; the semantics get read (does a fetch target match what the plugin claims to do?).
4. **Verdict** — A install / B quarantine only / C do not install.
5. **Quarantine validation** — separate `DSH_HOME`, read-only sandbox, throwaway profile.

## License

MIT
