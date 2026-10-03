# Beezybee Canteen Management System

GitHub Pages + Supabase version.

## Files
- `index.html` - website
- `config.example.js` - copy to `config.js` and add Supabase URL/key
- `supabase/schema.sql` - database, roles, RLS policies, analysis views and menu seed
- `menu.json` - original menu backup

## Local test
1. Copy `config.example.js` to `config.js`.
2. Fill in Supabase URL and publishable/anon key.
3. Open `index.html` through a local web server (recommended) or deploy to GitHub Pages.

Never put a Supabase `service_role` secret in frontend code.
