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

The repository root now contains `vercel.json`, so the whole repository can be imported directly into Vercel without manually selecting `web` as the Root Directory.

The root configuration runs:

- Install command: `cd web && npm install`
- Build command: `cd web && npm run build`
- Output directory: `web/dist`
- Framework: Vite
