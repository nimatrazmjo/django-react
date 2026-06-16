# Frontend — Vite + React 18 + TypeScript

Single-page application. Communicates with the Django backend exclusively through `/api/*` — routed via the Vite dev proxy in dev and nginx in staging/prod.

---

## Stack

| Tool | Version | Purpose |
|---|---|---|
| Vite | 5.x | Dev server, bundler |
| React | 18.x | UI |
| TypeScript | 5.x | Type safety |

---

## Project layout

```
frontend/
  src/
    main.tsx          ← React root mount
    App.tsx           ← Root component
    features/         ← One directory per product feature (add when needed)
      <feature>/
        components/   ← UI components for this feature
        hooks/        ← Custom hooks (data fetching, state)
        types.ts      ← TypeScript types local to this feature
        api.ts        ← fetch wrappers for /api/<feature>/* endpoints
    shared/
      components/     ← Reusable UI components (buttons, inputs, modals)
      hooks/          ← Shared hooks (useDebounce, useLocalStorage, etc.)
      types.ts        ← Shared TypeScript types
  index.html
  vite.config.ts
  tsconfig.json
```

---

## API calls

All HTTP calls go through `/api/` — **never hardcode a backend hostname** in component or hook files.

```ts
// src/features/orders/api.ts
export async function placeOrder(payload: PlaceOrderPayload): Promise<OrderCreated> {
  const res = await fetch("/api/orders/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json() as Promise<OrderCreated>;
}
```

In dev, Vite proxies `/api/*` → `http://backend:8000` (configured in `vite.config.ts`). In prod, nginx handles the same proxy.

---

## Component conventions

- Functional components only — no class components.
- One component per file; filename matches the export name (`OrderCard.tsx` exports `OrderCard`).
- Props interface named `<ComponentName>Props` and defined in the same file.
- Side effects and data fetching belong in custom hooks, not in component bodies.
- No inline `fetch` inside a component — always extract to `features/<f>/api.ts` and wrap in a hook.

---

## TypeScript rules

- `strict: true` — no implicit any, no unused vars.
- All API response shapes must have a corresponding TypeScript type in `features/<feature>/types.ts`.
- Never use `any`. Use `unknown` for genuinely opaque data and narrow it before use.
- `as` casts are allowed only in `api.ts` files where the response shape is known from the backend contract.

---

## Environment variables

All env vars exposed to the browser are prefixed `VITE_`. Access via `import.meta.env.VITE_*`.

| Variable | Description |
|---|---|
| `VITE_API_URL` | Backend origin — only used in `vite.config.ts` for the proxy target; not used in component code |
| `VITE_ENV` | `development` / `staging` / `production` |

Do not embed secrets in `VITE_*` variables — they are bundled into the JS output.

---

## Scripts

```bash
npm run dev       # Vite dev server on :5173 with HMR
npm run build     # tsc + vite build → dist/
npm run preview   # Preview the production build locally
npm run lint      # ESLint
```

---

## Skills

When generating frontend code:

- Always add TypeScript types for any new API response shape.
- Data-fetching logic belongs in a `use<Resource>` hook in `features/<feature>/hooks/`.
- Handle loading, error, and success states explicitly — never leave `loading` or `error` unhandled in a hook.
- AbortController patterns are required for any fetch inside a `useEffect` to prevent race conditions:
  ```ts
  useEffect(() => {
    const controller = new AbortController();
    fetchData(controller.signal).then(setData).catch(() => {});
    return () => controller.abort();
  }, [id]);
  ```
- When adding a new feature directory, also add its route to `App.tsx` and its types to `features/<feature>/types.ts`.
