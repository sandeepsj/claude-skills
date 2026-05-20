# claude-skills

Personal collection of [Claude Code](https://claude.com/claude-code) skills.

Each subdirectory is a single skill with a `SKILL.md` file (frontmatter + body). Claude Code auto-loads any skill placed under `~/.claude/skills/`.

## Skills

| Skill | What it does |
|---|---|
| [`doc-to-dashboard-md`](./doc-to-dashboard-md/) | Author Markdown that renders correctly in the [doc-to-dashboard](https://github.com/sandeepsj/doc-to-dashboard) viewer — front matter, Mermaid, KaTeX, callouts, glossary, footnotes. |
| [`react-spa-google-stack`](./react-spa-google-stack/) | Scaffold a static React SPA (Vite) with Google OAuth + Google Drive as the data store, deployed on GitHub Pages. Includes the canonical fix for the recurring "auth gone after refresh" bug and the centralized LLM proxy pattern. |
| [`cats-debug-validators`](./cats-debug-validators/) | Debug a failing CATS behavioral validator in the Vayu repo. Lists the silent-skip gates in `/otp/verify` → Flipkart ingestion, where `extractUserInfo`'s output actually lands (prefillData, not customer.*), the dropPrefix JSON field-name gotcha, and the LocalTime date-format gotcha. |

## Install on a new device

Clone anywhere, then symlink each skill folder into `~/.claude/skills/`:

```bash
git clone https://github.com/sandeepsj/claude-skills.git ~/code/claude-skills
mkdir -p ~/.claude/skills
ln -s ~/code/claude-skills/doc-to-dashboard-md ~/.claude/skills/doc-to-dashboard-md
```

Or symlink every skill at once:

```bash
for dir in ~/code/claude-skills/*/; do
  name=$(basename "$dir")
  [ "$name" = ".git" ] && continue
  ln -sfn "$dir" ~/.claude/skills/"$name"
done
```

Pull updates with `git pull` — symlinks pick up changes automatically.

## Add a new skill

1. Create a folder: `mkdir my-skill && cd my-skill`
2. Add `SKILL.md` with frontmatter:
   ```markdown
   ---
   name: my-skill
   description: One-line description of when Claude should activate this.
   ---

   # Skill body in Markdown
   ```
3. Symlink it into `~/.claude/skills/` and commit.
