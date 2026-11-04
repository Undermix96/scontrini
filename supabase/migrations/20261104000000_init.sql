-- Schema iniziale per l'app Scontrini.
-- Nessun accesso pubblico: RLS attiva senza policy, quindi solo la service role
-- (usata dalla Edge Function "api") può leggere e scrivere.

create table public.categories (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  color       text not null default '#607D8B',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table public.receipts (
  id              uuid primary key default gen_random_uuid(),
  merchant        text,
  purchased_at    timestamptz,
  total           numeric(12,2) not null default 0,
  currency        text not null default 'EUR',
  payment_method  text,
  notes           text,
  ai_model        text,
  ai_raw          jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index receipts_purchased_at_idx on public.receipts (purchased_at desc);

create table public.receipt_items (
  id           uuid primary key default gen_random_uuid(),
  receipt_id   uuid not null references public.receipts(id) on delete cascade,
  position     int  not null default 0,
  description  text not null,
  quantity     numeric(12,3),
  unit_price   numeric(12,2),
  total        numeric(12,2) not null default 0,
  category_id  bigint references public.categories(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index receipt_items_receipt_idx  on public.receipt_items (receipt_id);
create index receipt_items_category_idx on public.receipt_items (category_id);

alter table public.categories    enable row level security;
alter table public.receipts      enable row level security;
alter table public.receipt_items enable row level security;

-- Togli qualsiasi privilegio ai ruoli pubblici (difesa in profondità oltre a RLS).
revoke all on public.categories, public.receipts, public.receipt_items from anon, authenticated;

create or replace function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger receipts_updated_at before update on public.receipts
  for each row execute function public.set_updated_at();

insert into public.categories (name, color, sort_order) values
  ('Alimentari',    '#4CAF50', 10),
  ('Bevande',       '#03A9F4', 20),
  ('Casa',          '#795548', 30),
  ('Igiene',        '#9C27B0', 40),
  ('Salute',        '#F44336', 50),
  ('Trasporti',     '#FF9800', 60),
  ('Ristorazione',  '#E91E63', 70),
  ('Abbigliamento', '#3F51B5', 80),
  ('Svago',         '#009688', 90),
  ('Altro',         '#607D8B', 100);
