-- Pa que rinda la platica · base de datos
-- Se ejecuta una sola vez en Supabase: SQL Editor > New query > pegar todo > Run.
-- Se puede volver a ejecutar sin dañar los datos.
--
-- Cada persona entra con su correo y contraseña. Sus cuentas viven en un
-- "espacio"; la pareja se une a ese espacio con el código que viaja en el
-- enlace de invitación, y desde ahí los dos ven y anotan los mismos datos.

-- 1. Tablas -----------------------------------------------------------------

create table if not exists public.hogares (
  id uuid primary key default gen_random_uuid(),
  codigo text unique not null,                -- código de invitación (12 caracteres)
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

create or replace function public.mi_hogar() returns uuid
language sql stable security definer set search_path = public as $$
  select hogar_id from public.miembros where user_id = auth.uid()
$$;

create or replace function public.limpiar_codigo(p text) returns text
language sql immutable as $$
  select upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g'))
$$;

-- Espacio de quien consulta, cuántas personas lo comparten y si lo creó.
create or replace function public.mi_espacio() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', h.id,
    'codigo', h.codigo,
    'creador', h.creado_por = auth.uid(),
    'miembros', (select count(*) from public.miembros x where x.hogar_id = h.id))
  from public.miembros m
  join public.hogares h on h.id = m.hogar_id
  where m.user_id = auth.uid()
$$;

-- Crea un espacio nuevo para quien no tiene (o devuelve el suyo).
create or replace function public.crear_espacio() returns json
language plpgsql security definer set search_path = public as $$
declare
  h public.hogares;
  c text;
begin
  if auth.uid() is null then raise exception 'SIN_SESION'; end if;
  if public.mi_hogar() is not null then return public.mi_espacio(); end if;
  loop
    c := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    exit when not exists (select 1 from public.hogares where codigo = c);
  end loop;
  insert into public.hogares (codigo, creado_por) values (c, auth.uid()) returning * into h;
  insert into public.miembros (user_id, hogar_id) values (auth.uid(), h.id);
  return public.mi_espacio();
end $$;

-- Lo que ve quien abre un enlace de invitación antes de unirse: solo los nombres.
create or replace function public.ver_invitacion(p_codigo text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'yo', coalesce(d.data -> 'nombres' ->> 'yo', ''),
    'esp', coalesce(d.data -> 'nombres' ->> 'esp', ''),
    'modo', coalesce(d.data ->> 'modo', ''))
  from public.hogares h
  left join public.docs d on d.hogar_id = h.id and d.id = 'config'
  where auth.uid() is not null and h.codigo = public.limpiar_codigo(p_codigo)
$$;

-- Une a quien consulta al espacio del código (máximo dos personas por espacio).
-- Si tenía un espacio propio y queda sin nadie, se elimina.
create or replace function public.unirse_espacio(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
declare
  h public.hogares;
  anterior uuid := public.mi_hogar();
  n int;
begin
  if auth.uid() is null then raise exception 'SIN_SESION'; end if;
  select * into h from public.hogares where codigo = public.limpiar_codigo(p_codigo);
  if not found then raise exception 'CODIGO_NO_EXISTE'; end if;
  if anterior is not distinct from h.id then return public.mi_espacio(); end if;
  select count(*) into n from public.miembros where hogar_id = h.id;
  if n >= 2 then raise exception 'ESPACIO_LLENO'; end if;
  insert into public.miembros (user_id, hogar_id) values (auth.uid(), h.id)
    on conflict (user_id) do update set hogar_id = excluded.hogar_id;
  if anterior is not null then
    delete from public.hogares x
      where x.id = anterior
        and not exists (select 1 from public.miembros m where m.hogar_id = anterior);
  end if;
  return public.mi_espacio();
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

-- 3. Seguridad: cada cuenta ve solo su espacio --------------------------------

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
revoke all on function public.ver_invitacion(text) from public, anon;
revoke all on function public.unirse_espacio(text) from public, anon;
revoke all on function public.poner_item(text, text, text, jsonb) from public, anon;
grant execute on function public.mi_hogar() to authenticated;
grant execute on function public.mi_espacio() to authenticated;
grant execute on function public.crear_espacio() to authenticated;
grant execute on function public.ver_invitacion(text) to authenticated;
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
