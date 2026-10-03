-- Beezybee Canteen Management System
-- Run this in Supabase SQL Editor.
-- Auth users are created in Supabase Authentication > Users.

create extension if not exists pgcrypto;

create type public.app_role as enum ('owner','manager','cashier','chef');

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.app_role not null default 'cashier',
  created_at timestamptz not null default now()
);

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  item text not null unique,
  unit text not null,
  selling_price numeric(12,2) not null check (selling_price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  purchase_date date not null default current_date,
  item text not null,
  unit text not null,
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  total numeric(14,2) generated always as (quantity * unit_price) stored,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  sale_date date not null default current_date,
  item text not null,
  unit text not null,
  quantity numeric(12,2) not null check (quantity > 0),
  selling_price numeric(12,2) not null check (selling_price >= 0),
  total numeric(14,2) generated always as (quantity * selling_price) stored,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.stock_entries (
  id uuid primary key default gen_random_uuid(),
  stock_date date not null default current_date,
  item text not null,
  opening_stock numeric(12,2) not null default 0,
  added_cooked numeric(12,2) not null default 0,
  sold numeric(12,2) not null default 0,
  wasted numeric(12,2) not null default 0,
  closing_stock numeric(12,2) generated always as
    (opening_stock + added_cooked - sold - wasted) stored,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(stock_date, item)
);

create table if not exists public.cash_ups (
  id uuid primary key default gen_random_uuid(),
  cash_date date not null unique,
  opening_cash numeric(14,2) not null default 0,
  total_purchases numeric(14,2) not null default 0,
  total_sales numeric(14,2) not null default 0,
  closing_cash numeric(14,2) generated always as
    (opening_cash - total_purchases + total_sales) stored,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles(id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)), 'cashier')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.current_role()
returns public.app_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- Enable RLS on all application tables.
alter table public.profiles enable row level security;
alter table public.menu_items enable row level security;
alter table public.purchases enable row level security;
alter table public.sales enable row level security;
alter table public.stock_entries enable row level security;
alter table public.cash_ups enable row level security;

-- Profiles: users can see their own profile; owner can manage all profiles.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated
using (id = auth.uid() or public.current_role() = 'owner');

drop policy if exists profiles_owner_all on public.profiles;
create policy profiles_owner_all on public.profiles for all to authenticated
using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

-- MENU: everyone logged in can view. Owner/manager can edit.
drop policy if exists menu_select on public.menu_items;
create policy menu_select on public.menu_items for select to authenticated using (true);

drop policy if exists menu_modify on public.menu_items;
create policy menu_modify on public.menu_items for all to authenticated
using (public.current_role() in ('owner','manager'))
with check (public.current_role() in ('owner','manager'));

-- PURCHASES: all roles can view; owner/manager can insert/update/delete.
drop policy if exists purchases_select on public.purchases;
create policy purchases_select on public.purchases for select to authenticated using (true);

drop policy if exists purchases_modify on public.purchases;
create policy purchases_modify on public.purchases for all to authenticated
using (public.current_role() in ('owner','manager'))
with check (public.current_role() in ('owner','manager'));

-- SALES: all roles can view; owner/manager can insert/update/delete.
drop policy if exists sales_select on public.sales;
create policy sales_select on public.sales for select to authenticated using (true);

drop policy if exists sales_modify on public.sales;
create policy sales_modify on public.sales for all to authenticated
using (public.current_role() in ('owner','manager'))
with check (public.current_role() in ('owner','manager'));

-- STOCK: owner/manager can manage; others cannot access this table directly.
drop policy if exists stock_owner_manager on public.stock_entries;
create policy stock_owner_manager on public.stock_entries for all to authenticated
using (public.current_role() in ('owner','manager'))
with check (public.current_role() in ('owner','manager'));

-- CASH UP: all roles can view; owner/manager can manage.
drop policy if exists cash_select on public.cash_ups;
create policy cash_select on public.cash_ups for select to authenticated using (true);

drop policy if exists cash_modify on public.cash_ups;
create policy cash_modify on public.cash_ups for all to authenticated
using (public.current_role() in ('owner','manager'))
with check (public.current_role() in ('owner','manager'));

-- Helpful analysis views. They are intended for owner use in the UI.
create or replace view public.daily_sales as
select sale_date, sum(total) as total_sales
from public.sales group by sale_date order by sale_date desc;

create or replace view public.daily_purchases as
select purchase_date, sum(total) as total_purchases
from public.purchases group by purchase_date order by purchase_date desc;

create or replace view public.daily_net_sales as
select coalesce(s.sale_date,p.purchase_date) as date,
       coalesce(s.total_sales,0) as sales,
       coalesce(p.total_purchases,0) as purchases,
       coalesce(s.total_sales,0)-coalesce(p.total_purchases,0) as net_sales
from public.daily_sales s
full outer join public.daily_purchases p on p.purchase_date=s.sale_date
order by date desc;

-- Seed menu from the original Beezybee menu. Re-running is safe.
insert into public.menu_items(category,item,unit,selling_price)
values
('Starches','Plain Sadza (1 portion)','Plate',0.50),
('Starches','Plain Rice (1 portion)','Plate',1.00),
('Relishes / Add-ons','Vegetables (covo / rape / cabbage)','Portion',0.50),
('Relishes / Add-ons','Beans','Portion',1.00),
('Relishes / Add-ons','Matemba','Portion',0.50),
('Relishes / Add-ons','Beef','Portion',1.50),
('Relishes / Add-ons','Chicken Feet Stew','Portion',0.50),
('Relishes / Add-ons','Chicken','Portion',1.50),
('Relishes / Add-ons','Bream Fish','Portion',1.50),
('Relishes / Add-ons','Chicken Offals','Portion',1.00),
('Relishes / Add-ons','Gango','Portion',1.00),
('Relishes / Add-ons','Derere','Portion',0.50),
('Relishes / Add-ons','Muboora','Portion',0.50),
('Combo Plates','Sadza + Vegetables','Plate',1.00),
('Combo Plates','Sadza + Beans','Plate',1.50),
('Combo Plates','Rice + Beef Fried','Plate',2.00),
('Combo Plates','Sadza + Beef Stew + Vegetables','Plate',2.00),
('Combo Plates','Rice + Chicken Stew/Fried','Plate',2.50),
('Combo Plates','Sadza + Matemba','Plate',1.00),
('Combo Plates','Rice + Chicken Offals','Plate',2.00),
('Combo Plates','Sadza + Chicken + Vegetables','Plate',2.00),
('Combo Plates','Sadza + Chicken Offals + Vegetables','Plate',1.50),
('Combo Plates','Sadza + Derere','Plate',1.00),
('Combo Plates','Sadza + Muboora','Plate',1.00),
('Combo Plates','Sadza + Bream Fish + Vegetables','Plate',2.00),
('Combo Plates','Rice + Bream Fish','Plate',2.50),
('Combo Plates','Sadza + Gango + Vegetables','Plate',1.50),
('Combo Plates','Rice + Gango','Plate',2.00),
('Combo Plates','Chips + Chicken','Plate',2.50),
('Breakfast / Snacks','Burger','Piece',1.00),
('Breakfast / Snacks','Boiled Egg','Piece',0.50),
('Breakfast / Snacks','Bread Bun','Piece',0.50),
('Breakfast / Snacks','Tea','Cup',0.50),
('Breakfast / Snacks','Chips','Portion',1.00),
('Breakfast / Snacks','Sausage','Piece',1.00)
on conflict (item) do update set category=excluded.category, unit=excluded.unit, selling_price=excluded.selling_price;
