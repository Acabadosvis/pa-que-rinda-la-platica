-- Pa que rinda la platica · base de datos
-- Se ejecuta una sola vez en Supabase: SQL Editor > New query > pegar todo > Run.
-- Se puede volver a ejecutar sin dañar los datos.

-- 1. Tablas -----------------------------------------------------------------

-- Un "espacio" es donde viven las cuentas: de una persona o de una pareja.
create table if not exists public.hogares (
  id uuid primary key default gen_random_uuid(),
  codigo text unique not null,                -- código para invitar a la pareja
  creado_por uuid not null references auth.users (id) on delete cascade,
  creado timestamptz not null default now()
);

-- Cada cuenta (correo) pertenece a un solo espacio.
create table if not exists public.miembros (
  user_id uuid primary key references auth.users (id) on delete cascade,
  hogar_id uuid not null references public.hogares (id) on delete cascade,
  creado timestamptz not null default now()
);

-- Documentos del espacio: "config" (ajustes y obligaciones) y uno por quincena
-- ("q-2026-10-1", "q-2026-10-2", ...).
create table if not exists public.docs (
  hogar_id uuid not null references public.hogares (id) on delete cascade,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  actualizado timestamptz not null default now(),
  primary key (hogar_id, id)
);

-- 2. Funciones --------------------------------------------------------------

-- Espacio de quien hace la consulta.
create or replace function public.mi_hogar() returns uuid
language sql stable security definer set search_path = public as $$
  select hogar_id from public.miembros where user_id = auth.uid()
$$;

create or replace function public.mi_espacio() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', h.id, 'codigo', h.codigo)
  from public.miembros m
  join public.hogares h on h.id = m.hogar_id
  where m.user_id = auth.uid()
$$;

-- Crea un espacio nuevo para quien no tiene (o devuelve el que ya tiene).
create or replace function public.crear_espacio() returns json
language plpgsql security definer set search_path = public as $$
declare
  h public.hogares;
  c text;
begin
  if auth.uid() is null then raise exception 'SIN_SESION'; end if;
  select hh.* into h
    from public.miembros m join public.hogares hh on hh.id = m.hogar_id
    where m.user_id = auth.uid();
  if found then
    return json_build_object('id', h.id, 'codigo', h.codigo);
  end if;
  loop
    c := upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.hogares where codigo = c);
  end loop;
  insert into public.hogares (codigo, creado_por) values (c, auth.uid()) returning * into h;
  insert into public.miembros (user_id, hogar_id) values (auth.uid(), h.id);
  return json_build_object('id', h.id, 'codigo', h.codigo);
end $$;

-- Une a quien hace la consulta al espacio de su pareja (máximo dos personas).
create or replace function public.unirse_espacio(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
declare
  h public.hogares;
  n int;
begin
  if auth.uid() is null then raise exception 'SIN_SESION'; end if;
  select * into h from public.hogares where codigo = upper(trim(p_codigo));
  if not found then raise exception 'CODIGO_NO_EXISTE'; end if;
  select count(*) into n from public.miembros where hogar_id = h.id and user_id <> auth.uid();
  if n >= 2 then raise exception 'ESPACIO_LLENO'; end if;
  insert into public.miembros (user_id, hogar_id) values (auth.uid(), h.id)
    on conflict (user_id) do update set hogar_id = excluded.hogar_id;
  return json_build_object('id', h.id, 'codigo', h.codigo);
end $$;

-- Guarda, cambia o borra (p_val nulo) un ingreso o gasto dentro de una quincena.
-- Toca solo ese movimiento, así dos celulares pueden anotar a la vez sin pisarse.
create or replace function public.poner_item(p_doc text, p_kind text, p_id text, p_val jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  h uuid := public.mi_hogar();
begin
  if h is null then raise exception 'SIN_ESPACIO'; end if;
  if p_kind not in ('ing', 'gas')
     or p_doc !~ '^q-[0-9]{4}-[0-9]{2}-[12]$'
     or p_id is null or length(p_id) = 0 or length(p_id) > 40 then
    raise exception 'DATO_INVALIDO';
  end if;
  insert into public.docs (hogar_id, id, data)
    values (h, p_doc, '{"ing":{},"gas":{}}'::jsonb)
    on conflict (hogar_id, id) do nothing;
  if p_val is null or jsonb_typeof(p_val) = 'null' then
    update public.docs
      set data = data #- array[p_kind, p_id], actualizado = now()
      where hogar_id = h and id = p_doc;
  else
    update public.docs
      set data = jsonb_set(
            case when data ? p_kind then data else data || jsonb_build_object(p_kind, '{}'::jsonb) end,
            array[p_kind, p_id], p_val, true),
          actualizado = now()
      where hogar_id = h and id = p_doc;
  end if;
end $$;

-- 3. Seguridad: cada quien ve solo su espacio ---------------------------------

alter table public.hogares enable row level security;
alter table public.miembros enable row level security;
alter table public.docs enable row level security;

drop policy if exists "ver mi espacio" on public.hogares;
create policy "ver mi espacio" on public.hogares
  for select to authenticated using (id = public.mi_hogar());

drop policy if exists "ver miembros de mi espacio" on public.miembros;
create policy "ver miembros de mi espacio" on public.miembros
  for select to authenticated using (hogar_id = public.mi_hogar());

drop policy if exists "documentos de mi espacio" on public.docs;
create policy "documentos de mi espacio" on public.docs
  for all to authenticated
  using (hogar_id = public.mi_hogar())
  with check (hogar_id = public.mi_hogar());

revoke all on public.hogares, public.miembros, public.docs from anon;
grant select on public.hogares, public.miembros to authenticated;
grant select, insert, update, delete on public.docs to authenticated;

revoke all on function public.mi_hogar() from public, anon;
revoke all on function public.mi_espacio() from public, anon;
revoke all on function public.crear_espacio() from public, anon;
revoke all on function public.unirse_espacio(text) from public, anon;
revoke all on function public.poner_item(text, text, text, jsonb) from public, anon;
grant execute on function public.mi_hogar() to authenticated;
grant execute on function public.mi_espacio() to authenticated;
grant execute on function public.crear_espacio() to authenticated;
grant execute on function public.unirse_espacio(text) to authenticated;
grant execute on function public.poner_item(text, text, text, jsonb) to authenticated;

-- 4. Sincronización en vivo entre dispositivos --------------------------------

do $$
begin
  alter publication supabase_realtime add table public.docs;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
