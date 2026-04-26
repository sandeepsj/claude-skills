---
name: react-spa-google-stack
description: Build a static React SPA (Vite) with Google OAuth + Google Drive as the data store, deployed on GitHub Pages. Use when scaffolding or maintaining a serverless personal app where the user's Google account is the auth + storage layer. Covers the canonical fix for the "auth gone after page refresh" bug, GIS token client setup, Drive API patterns, and the centralized LLM proxy for AI calls.
---

# React SPA + Google Auth + Google Drive

A repeatable architecture for personal/static apps:

- **Hosting**: GitHub Pages (free, static)
- **Auth**: Google Identity Services (GIS) token client
- **Data store**: User's own Google Drive (`drive.file` scope)
- **AI calls** (optional): Centralized LLM proxy at `https://llm-proxy-smoky.vercel.app` — no per-project API keys

The SPA is pure static files. Drive is the database. No backend to maintain.

---

## ⚠️ The recurring "auth disappears on refresh" bug — read this first

**Symptom**: User signs in → uses the app → hits F5 → back at the login screen. Has to reauthenticate.

**Root cause**: GIS token clients hold the access token in JavaScript memory only. A page refresh wipes it.

**Wrong fixes that look right but fail**:
- Calling `tokenClient.requestAccessToken({ prompt: '' })` on mount to silently re-auth — modern browsers block this as an **unsolicited popup** (the user didn't click anything). Sometimes works in dev, fails in prod.
- Storing the token in `localStorage` "to be safe" — token only lives 1 hour anyway, and `localStorage` keeps it around longer than necessary across tabs.
- Refresh tokens — Google does not issue refresh tokens to public SPAs. Don't go looking for one.

### Canonical fix

Two storage buckets, read **synchronously on mount** with no GIS popup and no network call:

| Item | Storage | Why |
|---|---|---|
| User info (email, name, picture) | `localStorage` | Survives tab close. Cheap to keep — used for avatar/UI only. |
| Access token | `sessionStorage` | Cleared when the tab closes. Matches the token's natural ~1hr lifetime. |

**On sign-in** → save both. **On mount** → read both, populate state, done. **On API 401** → clear both, show login. **On sign-out** → clear both + revoke.

```ts
// services/googleAuth.ts — minimal canonical version
const USER_KEY = 'app_user'
const TOKEN_KEY = 'app_token'

export function saveSession(user: GoogleUser, token: string) {
  localStorage.setItem(USER_KEY, JSON.stringify(user))
  sessionStorage.setItem(TOKEN_KEY, token)
}

export function loadSession(): AuthState | null {
  const token = sessionStorage.getItem(TOKEN_KEY)
  const raw = localStorage.getItem(USER_KEY)
  if (!token || !raw) return null
  return { isLoggedIn: true, user: JSON.parse(raw), accessToken: token }
}

export function clearSession() {
  localStorage.removeItem(USER_KEY)
  sessionStorage.removeItem(TOKEN_KEY)
}
```

```tsx
// hooks/useAuth.ts — the mount-time restore
useEffect(() => {
  const state = loadSession()
  if (state) setAuth(state)   // synchronous, no popup, no fetch
}, [])
```

**Recovery flow when the stored token has expired**:
1. Drive/proxy API returns 401.
2. Catch the 401 in your fetch wrapper → call `clearSession()` and route to login.
3. User clicks "Sign in" → fresh token → `saveSession()` again.

Do **not** try to validate the token on mount via `userinfo` — that adds a network round-trip to every page load. Just trust storage and let the first 401 trigger re-auth.

---

## Project scaffold

### Dependencies

```bash
npm create vite@latest my-app -- --template react-ts
cd my-app
npm install react-router-dom
```

### `vite.config.ts`

```ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  base: '/<repo-name>/',          // GitHub Pages — must match repo name. Use '/' for custom domain.
  plugins: [react()],
  resolve: { alias: { '@': path.resolve(dirname, './src') } },
})
```

### `index.html`

Load the GIS client script in `<head>`:

```html
<script src="https://accounts.google.com/gsi/client" async defer></script>
```

### Routing

Use `HashRouter`. GitHub Pages returns 404 on deep links because there's no server-side rewrite — `HashRouter` sidesteps it by routing client-side via `#`.

```tsx
import { HashRouter, Routes, Route } from 'react-router-dom'
```

### Env vars

Vite only exposes vars prefixed with `VITE_`. Required:

```
VITE_GOOGLE_CLIENT_ID=...apps.googleusercontent.com
```

In GitHub Actions, **secrets** are referenced as `${{ secrets.X }}`, **variables** as `${{ vars.X }}`. Mixing them up silently produces empty strings at build time.

---

## Google Cloud setup (one-time per project)

1. [console.cloud.google.com](https://console.cloud.google.com) → new project.
2. **APIs & Services → Library** → enable **Google Drive API**.
3. **APIs & Services → Credentials** → **Create OAuth client ID** → **Web application**.
4. **Authorized JavaScript origins**:
   - `http://localhost:5173` (dev)
   - `https://<username>.github.io` (prod)
5. **OAuth consent screen** → External → add your email as a test user (the app stays in test mode; that's fine for personal use).
6. Copy the Client ID into `VITE_GOOGLE_CLIENT_ID`.

---

## Sign-in flow (GIS token client)

```ts
const SCOPES = 'https://www.googleapis.com/auth/drive.file openid email profile'

export async function signIn(): Promise<AuthState> {
  await loadGisScript()
  return new Promise((resolve, reject) => {
    const tokenClient = google.accounts.oauth2.initTokenClient({
      client_id: getClientId()!,
      scope: SCOPES,
      callback: async (response) => {
        if (response.error) return reject(new Error(response.error))
        const user = await fetchUserInfo(response.access_token)
        saveSession(user, response.access_token)
        resolve({ isLoggedIn: true, user, accessToken: response.access_token })
      },
      error_callback: (err) => reject(new Error(err.message)),
    })
    tokenClient.requestAccessToken()   // user click → popup → token
  })
}

async function fetchUserInfo(token: string) {
  const res = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error(`userinfo ${res.status}`)
  return res.json()  // { email, name, picture, ... }
}
```

`requestAccessToken()` (no `prompt` arg) MUST be triggered from a user click — browsers block popups otherwise.

---

## Scope choice: `drive.file` vs `drive`

| Scope | Visible in user's Drive UI? | Sees other files? | Use when |
|---|---|---|---|
| `drive.file` | Yes for files **created via this OAuth client** — they appear in My Drive normally | No | Default. Privacy-friendly. |
| `drive` | Yes, all | Yes | App needs to manage user's existing files |
| `drive.appdata` | **No** — hidden in `appDataFolder` | No | Avoid — files are invisible to the user; defeats the "Drive as data store" model |

`drive.file` files **do** show up in the user's Drive. The often-repeated claim that they're hidden is wrong for files created via your OAuth client (it's only true for `drive.appdata`).

---

## Drive API quick reference

- Base: `https://www.googleapis.com/drive/v3`
- Upload: `https://www.googleapis.com/upload/drive/v3`
- Every request: `Authorization: Bearer <token>`

### Folder layout pattern

```
<App Folder>/
  <entry-id>/
    content.md
    metadata.json
    drawing.png
```

### Find or create the app folder

```ts
const q = `name='${APP_FOLDER}' and mimeType='application/vnd.google-apps.folder' and trashed=false`
const url = `${DRIVE_API}/files?q=${encodeURIComponent(q)}&fields=files(id)&spaces=drive`
```

### Create a text file (multipart upload)

```ts
const metadata = { name: 'content.md', parents: [folderId], mimeType: 'text/markdown' }
const boundary = '---boundary'
const body =
  `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n` +
  `--${boundary}\r\nContent-Type: text/markdown; charset=UTF-8\r\n\r\n${content}\r\n` +
  `--${boundary}--`

await fetch(`${UPLOAD_API}/files?uploadType=multipart&fields=id`, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${token}`,
    'Content-Type': `multipart/related; boundary=${boundary}`,
  },
  body,
})
```

### Update / read / delete

```ts
// PATCH content
fetch(`${UPLOAD_API}/files/${id}?uploadType=media`, { method: 'PATCH', headers: {...}, body: content })

// Read text
fetch(`${DRIVE_API}/files/${id}?alt=media`, { headers: {...} }).then(r => r.text())

// Delete
fetch(`${DRIVE_API}/files/${id}`, { method: 'DELETE', headers: {...} })
```

### `appProperties` for cheap listing

Store small key-value metadata on a folder so you can list dashboard entries without downloading every file.

**Hard limit**: each key + each value ≤ 124 bytes UTF-8. Truncate values to ~100 chars defensively.

```ts
appProperties: {
  title: title.slice(0, 100),
  excerpt: body.slice(0, 100),
  createdAt: new Date().toISOString(),
}

// Fetch with: &fields=files(id,name,modifiedTime,appProperties)
```

### Quotas (effectively infinite for personal apps)

1B queries/day, 20K/100s/user. Auto-save every 30s with ~10 calls = nowhere close.

---

## Centralized LLM proxy (skip per-project Vercel functions)

For AI calls, use the existing proxy instead of standing up serverless functions per project.

- **Repo**: github.com/sandeepsj/llm-proxy
- **Endpoint**: `POST https://llm-proxy-smoky.vercel.app/api/proxy`
- **Auth**: same Google access token the SPA already has (the proxy verifies it and checks an allowlist).

```ts
const PROXY = 'https://llm-proxy-smoky.vercel.app/api/proxy'

export async function llmProxy(
  provider: 'openai' | 'anthropic' | 'google',
  endpoint: string,
  body: Record<string, unknown>,
  token: string,
) {
  const res = await fetch(PROXY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ provider, endpoint, body }),
  })
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `proxy ${res.status}`)
  return res
}
```

| Use case | provider | endpoint |
|---|---|---|
| Embeddings (free, 768d) | `google` | `models/gemini-embedding-001:embedContent` |
| Claude chat | `anthropic` | `messages` |
| OpenAI chat | `openai` | `chat/completions` |
| Gemini chat | `google` | `models/gemini-2.0-flash:generateContent` |
| Image gen | `openai` | `images/generations` |

If you get **403** from the proxy, your email isn't on the allowlist — add it via `ALLOWED_USERS` in the proxy's Vercel env vars. **401** means the Google token expired (1hr cap) — re-auth in the SPA.

---

## GitHub Pages deploy

`.github/workflows/deploy.yml`:

```yaml
name: Deploy
on:
  push: { branches: [main] }
  workflow_dispatch:
permissions: { contents: read, pages: write, id-token: write }
concurrency: { group: pages, cancel-in-progress: true }
jobs:
  build:
    runs-on: ubuntu-latest
    environment: { name: github-pages, url: '${{ steps.deploy.outputs.page_url }}' }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npm run build
        env:
          VITE_GOOGLE_CLIENT_ID: ${{ secrets.VITE_GOOGLE_CLIENT_ID }}
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with: { path: dist }
      - id: deploy
        uses: actions/deploy-pages@v4
```

Then **Settings → Pages → Source → GitHub Actions**.

---

## Common gotchas

| Symptom | Cause / Fix |
|---|---|
| Sign-in works, refresh logs out | Not using the `localStorage` user + `sessionStorage` token pattern above. |
| `prompt: ''` silent refresh sometimes blocked | Browsers treat it as unsolicited popup. Don't rely on it — just trust storage and re-auth on 401. |
| GitHub Pages 404 on `/route` | Use `HashRouter`, not `BrowserRouter`. |
| Assets 404 in prod | Missing `base: '/<repo-name>/'` in `vite.config.ts`. |
| Favicon 404 | Use `href="./favicon.ico"` (relative), not `/favicon.ico`. |
| Env var empty at runtime | Must be `VITE_*` prefix. In CI, secrets vs vars: `${{ secrets.X }}` vs `${{ vars.X }}`. |
| `propertyLengthLimitExceeded` on Drive write | `appProperties` key+value cap is 124 bytes each. Truncate to ~100 chars. |
| `origin_mismatch` from GIS | Add the exact origin (scheme + host + port) to Authorized JavaScript Origins in Cloud Console. |
| `Invalid time value` | Guard `new Date(x).toISOString()` with `!isNaN(new Date(x).getTime())`. |
| Vercel tries `next build` | Set Framework Preset to **Other** in project settings. |

---

## Minimal file checklist for a new project

- [ ] `vite.config.ts` with `base` set
- [ ] `index.html` with GIS script tag
- [ ] `src/services/googleAuth.ts` — sign-in, save/load/clear session, restore on mount
- [ ] `src/services/drive.ts` — folder helpers, multipart upload, list with `appProperties`
- [ ] `src/hooks/useAuth.ts` — `useEffect` calls `loadSession()` synchronously
- [ ] `src/lib/llm-proxy.ts` (if AI needed)
- [ ] `App.tsx` with `HashRouter`
- [ ] `.github/workflows/deploy.yml`
- [ ] `VITE_GOOGLE_CLIENT_ID` in GitHub Secrets
- [ ] OAuth client's authorized origins include both `localhost:5173` and the Pages URL
