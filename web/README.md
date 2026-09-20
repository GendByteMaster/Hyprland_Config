# Hyprland_Config web page

React + TypeScript landing page for the Hyprland_Config project.

## Development

```bash
cd web
npm install
npm run dev
```

## Production build

```bash
npm run build
```

The generated static site is written to `web/dist/`.

## Vercel

Use `web` as the Vercel **Root Directory**. The Vercel config is stored inside `web/vercel.json`, so commands run directly from the app root without an extra `cd web`.

Vercel uses the package scripts automatically:

- Install command: `npm install`
- Build command: `npm run build`
- Output directory: `dist`
- Framework: Vite
