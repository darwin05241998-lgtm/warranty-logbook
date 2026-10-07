# Warranty Logbook

A responsive warranty logbook. The site uses Supabase for email/password sign-in, branch access, service records, and private slip attachments.

## Supabase setup

1. Open the Supabase project SQL Editor.
2. Run [`supabase-setup.sql`](./supabase-setup.sql).
   - The script is safe to rerun after the existing schema has been created. It adds the atomic slip-number RPC and enables Realtime updates for service records.
3. In Supabase Authentication URL settings, set the Site URL to the GitHub Pages address and add that same address to the allowed redirect URLs.

The project URL and publishable browser key are configured in `index.html`. Publishable keys are intended for browser use; never add a Supabase secret or `service_role` key to this repository.

## Publish with GitHub Pages

1. Create a GitHub repository named `warranty-logbook` and push these project files to its `main` branch.
2. In the repository, open **Settings → Pages** and set the build and deployment source to **GitHub Actions**.
3. The workflow in `.github/workflows/pages.yml` deploys the site after each push to `main`. GitHub shows the published URL in **Settings → Pages** and in the workflow run.
4. Add the published URL to Supabase Authentication URL settings, then open that URL and create your account.

The site uses the same account on phone and computer. Supabase row-level security limits each account to branches it belongs to.
New records are assigned slip numbers on the server to avoid collisions when two devices save at the same time. Changes to records appear on other open devices through Supabase Realtime.
