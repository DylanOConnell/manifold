-- This file is autogenerated from regen-schema.ts
create table if not exists
  group_embeddings (
    group_id text not null,
    created_time timestamp without time zone default now() not null,
    embedding vector (1536) not null
  );

-- Foreign Keys
alter table group_embeddings
add constraint public_group_embeddings_group_id_fkey foreign key (group_id) references groups (id) on update cascade on delete cascade;

-- Policies
alter table group_embeddings enable row level security;

drop policy if exists "admin write access" on group_embeddings;

create policy "admin write access" on group_embeddings to service_role for all;

drop policy if exists "public read" on group_embeddings;

create policy "public read" on group_embeddings for
select
  using (true);

-- Indexes
drop index if exists group_embeddings_pkey;

create unique index group_embeddings_pkey on public.group_embeddings using btree (group_id);
