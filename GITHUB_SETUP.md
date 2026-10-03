# Beezybee: GitHub Desktop setup

1. Open GitHub Desktop.
2. Keep the repository shown as `Final Canteen System` if that is the repository you want to use.
3. Click `Show in Finder`.
4. Replace/copy the contents of this folder into that repository folder. Keep `index.html` at the repository root.
5. In GitHub Desktop, return to `Changes`.
6. Enter commit summary: `Prepare Beezybee canteen web system`.
7. Click `Commit to main`.
8. Click `Publish repository` if the repository is not online yet.
9. On GitHub.com open the repository > Settings > Pages.
10. Under Build and deployment choose `GitHub Actions` (or Deploy from a branch for a simple static site).
11. Push/commit changes. GitHub Pages publishes the site.

Important: GitHub Pages hosts the frontend. It is not the secure database. Supabase supplies authentication, Postgres data storage and row-level permissions.

## Supabase
1. Create a Supabase project.
2. Open SQL Editor and run `supabase/schema.sql`.
3. In Authentication > Users create five accounts with email + password.
4. After each account exists, open SQL Editor and set the profile role, for example:

update public.profiles
set role='owner', display_name='Owner'
where id=(select id from auth.users where email='OWNER_EMAIL');

Repeat with `manager`, `cashier`, `cashier`, and `chef`.
5. Copy `config.example.js` to `config.js` and enter the Supabase project URL and browser-safe publishable/anon key.
6. Do not upload a service_role key.

The supplied `index.html` is the local/demo UI. The next development step is wiring its forms to the Supabase tables. Do not treat the demo localStorage login as production security.
