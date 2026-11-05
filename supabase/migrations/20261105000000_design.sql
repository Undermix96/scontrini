-- Nuovo design: avvisi persistenti, doppioni salvati, nuova palette delle categorie.

alter table public.receipts
  add column dismissed_warnings text[] not null default '{}',
  add column duplicate_of uuid references public.receipts(id) on delete set null;

create index receipts_duplicate_of_idx on public.receipts (duplicate_of);

-- Doppioni già presenti: stesso totale e data/ora entro un minuto.
-- Ogni scontrino punta al più vecchio fra quelli simili.
update public.receipts r
set duplicate_of = d.other_id
from (
  select distinct on (a.id) a.id, b.id as other_id
  from public.receipts a
  join public.receipts b
    on b.id <> a.id
   and b.total = a.total
   and b.purchased_at between a.purchased_at - interval '60 seconds' and a.purchased_at + interval '60 seconds'
   and (b.created_at, b.id) < (a.created_at, a.id)
  order by a.id, b.created_at
) d
where r.id = d.id;

-- Nuova palette per le categorie predefinite.
update public.categories c set color = v.color
from (values
  ('Alimentari',    '#4CC38A'),
  ('Bevande',       '#F0A35A'),
  ('Casa',          '#5AA9F0'),
  ('Igiene',        '#E67AC4'),
  ('Salute',        '#F26D6D'),
  ('Trasporti',     '#6FD3D3'),
  ('Ristorazione',  '#E8D45A'),
  ('Abbigliamento', '#7C8CF8'),
  ('Svago',         '#A99CFF'),
  ('Altro',         '#8E8C9C')
) as v(name, color)
where c.name = v.name;

alter table public.categories alter column color set default '#8E8C9C';
