# packbound.net

Static marketing site + privacy policy for the Packbound app. Plain HTML/CSS,
no build step, no dependencies - open `index.html` directly in a browser to
preview locally.

- `index.html` — landing page (features, how it works, privacy highlights)
- `privacy.html` — full privacy policy (also the URL to give app stores when
  they ask for one)
- `styles.css` — shared design system (brand colors/fonts, matches
  `branding/packbound-brand-guide.html`)
- `favicon.svg` — copy of `branding/packbound-icon.svg`

## Deploying

The repo's `firebase.json` already points a `hosting` config at this folder,
so from the repo root:

```bash
firebase deploy --only hosting
```

To attach the `packbound.net` custom domain, add it under **Hosting → Add
custom domain** in the Firebase console for the `convoy-app-ajd` project,
then point the domain's DNS at the records Firebase gives you.

Any other static host (Netlify, GitHub Pages, plain nginx) works too - it's
just three files with no server-side dependency.
