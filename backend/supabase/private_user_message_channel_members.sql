-- This file is autogenerated from regen-schema.ts
create table if not exists
  private_user_message_channel_members (
    id bigint not null,
    created_time timestamp with time zone default now() not null,
    channel_id bigint not null,
    user_id text not null,
    role text default 'member'::text not null,
    status text default 'proposed'::text not null,
    notify_after_time timestamp with time zone default now() not null
  );

-- Indexes
drop index if exists private_user_message_channel_members_pkey;

create unique index private_user_message_channel_members_pkey on public.private_user_message_channel_members using btree (id);

drop index if exists unique_user_channel;

create unique index unique_user_channel on public.private_user_message_channel_members using btree (channel_id, user_id);

drop index if exists pumcm_members_idx;

create index pumcm_members_idx on public.private_user_message_channel_members using btree (channel_id, user_id);
