## Development

This is an Astro app using Vite Plus, React, and Astryx.

- Astro MCP is available as `mcp_servers.astro-docs`
- Start the app with `vp run dev --background` and manage it with `vp run dev status`, `vp run dev logs`, and `vp run dev stop`.
- Run `vp check`, `vp test`, and `vp run build` before handing off changes.
- Before adding UI, run `npx astryx build "<idea>"`, inspect named templates, and read the component docs for every Astryx component used.
- Full pages use `AppShell`; secondary regions use `Layout` and `LayoutPanel`.
- Use Astryx layout primitives instead of raw `<div>` elements. Dense records are rows, while cards are reserved for independent dashboard widgets.
- Use semantic theme tokens for styling. Edit `src/theme/academic.ts`, then regenerate `src/theme/academic.generated.css` with `node scripts/build-theme.mjs`.
- Course presentation remains in the root `courses/` MDX collection. Prototype learner state lives in `src/data/learning.json` behind the typed catalog adapter.
