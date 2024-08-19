-- This file is autogenerated from regen-schema.ts
create
or replace function public.add_creator_name_to_description (data jsonb) returns text language sql immutable as $function$
select * from CONCAT_WS(
        ' '::text,
        data->>'creatorName',
        public.extract_text_from_rich_text_json(data->'description')
    )
$function$;

create
or replace function public.calculate_earth_distance_km (
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
) returns double precision language plpgsql immutable as $function$
DECLARE
  radius_earth_km CONSTANT FLOAT := 6371;
  delta_lat FLOAT;
  delta_lon FLOAT;
  a FLOAT;
  c FLOAT;
BEGIN
  -- Convert degrees to radians
  lat1 := RADIANS(lat1);
  lon1 := RADIANS(lon1);
  lat2 := RADIANS(lat2);
  lon2 := RADIANS(lon2);

  -- Calculate differences
  delta_lat := lat2 - lat1;
  delta_lon := lon2 - lon1;

  -- Apply Haversine formula
  a := SIN(delta_lat / 2) ^ 2 + COS(lat1) * COS(lat2) * SIN(delta_lon / 2) ^ 2;
  c := 2 * ATAN2(SQRT(a), SQRT(1 - a));

  -- Calculate distance
  RETURN radius_earth_km * c;
END;
$function$;

create
or replace function public.can_access_private_messages (channel_id bigint, user_id text) returns boolean language sql parallel SAFE as $function$
select exists (
    select 1 from private_user_message_channel_members
    where private_user_message_channel_members.channel_id = $1
      and private_user_message_channel_members.user_id = $2
)
$function$;

create
or replace function public.close_contract_embeddings (
  input_contract_id text,
  similarity_threshold double precision,
  match_count integer
) returns table (
  contract_id text,
  similarity double precision,
  data jsonb
) language sql as $function$ WITH embedding AS (
    SELECT embedding
    FROM contract_embeddings
    WHERE contract_id = input_contract_id
)
    SELECT contract_id,
           similarity,
           data
    FROM public.search_contract_embeddings(
                 (
                     SELECT embedding
                     FROM embedding
                 ),
                 similarity_threshold,
                 match_count + 500
         )
             join contracts on contract_id = contracts.id
    where contract_id != input_contract_id
      and resolution_time is null
      and contracts.visibility = 'public'
    order by similarity * similarity * importance_score desc
    limit match_count;
$function$;

create
or replace function public.count_recent_comments (contract_id text) returns integer language sql as $function$
  SELECT COUNT(*)
  FROM contract_comments
  WHERE contract_id = $1
    AND created_time >= NOW() - INTERVAL '1 DAY'
$function$;

create
or replace function public.count_recent_comments_by_contract () returns table (contract_id text, comment_count integer) language sql as $function$
  SELECT
    contract_id,
    COUNT(*) AS comment_count
  FROM
    contract_comments
  WHERE
    created_time >= NOW() - INTERVAL '1 DAY'
  GROUP BY
    contract_id
  ORDER BY
    comment_count DESC;
$function$;

create
or replace function public.creator_leaderboard (limit_n integer) returns table (
  user_id text,
  total_traders integer,
  name text,
  username text,
  avatar_url text
) language sql stable parallel SAFE as $function$
  select id as user_id, (data->'creatorTraders'->'allTime')::int as total_traders, name, username, data->>'avatarUrl' as avatar_url
  from users
  order by total_traders desc
  limit limit_n
$function$;

create
or replace function public.creator_rank (uid text) returns integer language sql stable parallel SAFE as $function$
  select count(*) + 1
  from users
  where data->'creatorTraders'->'allTime' > (select data->'creatorTraders'->'allTime' from users where id = uid)
$function$;

create
or replace function public.date_to_midnight_pt (d date) returns timestamp without time zone language sql immutable parallel SAFE as $function$
  select timezone('America/Los_Angeles', d::timestamp)::timestamptz
$function$;

create
or replace function public.extract_text_from_rich_text_json (description jsonb) returns text language sql immutable as $function$
WITH RECURSIVE content_elements AS (
    SELECT jsonb_array_elements(description->'content') AS element
    WHERE jsonb_typeof(description) = 'object'
    UNION ALL
    SELECT jsonb_array_elements(element->'content')
    FROM content_elements
    WHERE element->>'type' = 'paragraph' AND element->'content' IS NOT NULL
),
               text_elements AS (
                   SELECT jsonb_array_elements(element->'content') AS text_element
                   FROM content_elements
                   WHERE element->>'type' = 'paragraph'
               ),
               filtered_text_elements AS (
                   SELECT text_element
                   FROM text_elements
                   WHERE jsonb_typeof(text_element) = 'object' AND text_element->>'type' = 'text'
               ),
               all_text_elements AS (
                   SELECT filtered_text_elements.text_element->>'text' AS text
                   FROM filtered_text_elements
               )
SELECT
    CASE
        WHEN jsonb_typeof(description) = 'string' THEN description::text
        ELSE COALESCE(string_agg(all_text_elements.text, ' '), '')
        END
FROM
    all_text_elements;
$function$;

create
or replace function public.firebase_uid () returns text language sql stable parallel SAFE leakproof as $function$
  select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::text;
$function$;

create
or replace function public.get_average_rating (user_id text) returns numeric language plpgsql as $function$
DECLARE
  result numeric;
BEGIN
  SELECT AVG(rating)::numeric INTO result
  FROM reviews
  WHERE vendor_id = user_id;
  RETURN result;
END;
$function$;

create
or replace function public.get_compatibility_questions_with_answer_count () returns setof love_question_with_count_type language plpgsql as $function$
BEGIN
    RETURN QUERY 
    SELECT 
        love_questions.*,
        COUNT(love_compatibility_answers.question_id) as answer_count
    FROM 
        love_questions
    LEFT JOIN 
        love_compatibility_answers ON love_questions.id = love_compatibility_answers.question_id
        WHERE love_questions.answer_type='compatibility_multiple_choice'
    GROUP BY 
        love_questions.id
    ORDER BY 
        answer_count DESC;
END;
$function$;

create
or replace function public.get_contract_metrics_with_contracts (uid text, count integer) returns table (contract_id text, metrics jsonb, contract jsonb) language sql immutable parallel SAFE as $function$
select ucm.contract_id, ucm.data as metrics, c.data as contract
from user_contract_metrics as ucm
join contracts as c on c.id = ucm.contract_id
where ucm.user_id = uid
order by ((ucm.data)->'lastBetTime')::bigint desc
limit count
$function$;

create
or replace function public.get_contract_metrics_with_contracts (uid text, count integer, start integer) returns table (contract_id text, metrics jsonb, contract jsonb) language sql stable as $function$select ucm.contract_id,
       ucm.data as metrics,
       c.data as contract
from user_contract_metrics as ucm
         join contracts as c on c.id = ucm.contract_id
where ucm.user_id = uid
  and ucm.data->'lastBetTime' is not null
  and ucm.answer_id is null
order by ((ucm.data)->'lastBetTime')::bigint desc offset start
    limit count$function$;

create
or replace function public.get_contract_voters (this_contract_id text) returns table (data json) language sql parallel SAFE as $function$
  SELECT users.data from users join votes on votes.user_id = users.id where votes.contract_id = this_contract_id;
$function$;

create
or replace function public.get_contracts_in_group_slugs_1 (
  contract_ids text[],
  p_group_slugs text[],
  ignore_slugs text[]
) returns table (data json, importance_score numeric) language sql stable parallel SAFE as $function$
select data, importance_score
from contracts
where id = any(contract_ids)
  and visibility = 'public'
  and (group_slugs && p_group_slugs)
  and not (group_slugs && ignore_slugs)
$function$;

create
or replace function public.get_cpmm_pool_prob (pool jsonb, p numeric) returns numeric language plpgsql immutable parallel SAFE as $function$
declare
    p_no numeric := (pool->>'NO')::numeric;
    p_yes numeric := (pool->>'YES')::numeric;
    no_weight numeric := p * p_no;
    yes_weight numeric := (1 - p) * p_yes + p * p_no;
begin
    return case when yes_weight = 0 then 1 else (no_weight / yes_weight) end;
end
$function$;

create
or replace function public.get_daily_claimed_boosts (user_id text) returns table (total numeric) language sql as $function$
with daily_totals as (
    select
        SUM(t.amount) as total
    from txns t
    where t.created_time > now() - interval '1 day'
      and t.category = 'MARKET_BOOST_REDEEM'
      and t.to_id = user_id
    group by date_trunc('day', t.created_time)
)
select total from daily_totals
order by total desc;
$function$;

create
or replace function public.get_donations_by_charity () returns table (
  charity_id text,
  num_supporters bigint,
  total numeric
) language sql as $function$
    select to_id as charity_id,
      count(distinct from_id) as num_supporters,
      sum(case when token = 'M$'
        then amount / 100
        else amount / 1000 end
      ) as total
    from txns
    where category = 'CHARITY'
    group by to_id
    order by total desc
$function$;

create
or replace function public.get_group_contracts (this_group_id text) returns table (data json) language sql immutable parallel SAFE as $function$
select contracts.data from 
    contracts join group_contracts on group_contracts.contract_id = contracts.id
    where group_contracts.group_id = this_group_id 
    $function$;

create
or replace function public.get_love_question_answers_and_lovers (p_question_id bigint) returns setof other_lover_answers_type language plpgsql as $function$
BEGIN
    RETURN QUERY
    SELECT 
        love_answers.question_id,
        love_answers.created_time,
        love_answers.free_response,
        love_answers.multiple_choice,
        love_answers.integer,
        lovers.age,
        lovers.gender,
        lovers.city,
        users.data
    FROM
        lovers
    JOIN
        love_answers ON lovers.user_id = love_answers.creator_id
    join 
        users on lovers.user_id = users.id 
    WHERE
        love_answers.question_id = p_question_id
    order by love_answers.created_time desc;
END;
$function$;

create
or replace function public.get_market_ads (uid text) returns table (
  ad_id text,
  market_id text,
  ad_funds numeric,
  ad_cost_per_view numeric,
  market_data jsonb
) language sql as $function$
--with all the redeemed ads (has a txn)
with redeemed_ad_ids as (
  select
    from_id
  from
    txns
  where
    category = 'MARKET_BOOST_REDEEM'
    and to_id = uid
),
-- with the user embedding
user_embedding as (
    select interest_embedding, disinterest_embedding
    from user_embeddings
  where user_id = uid
),
--with all the ads that haven't been redeemed, by closest to your embedding
unredeemed_market_ads as (
  select
    id, market_id, funds, cost_per_view, embedding
  from
    market_ads
  where 
    market_ads.user_id != uid -- hide your own ads; comment out to debug
    and not exists (
      SELECT 1
      FROM redeemed_ad_ids
      WHERE from_id = market_ads.id
    )
    and market_ads.funds >= cost_per_view
    and coalesce(embedding <=> (select disinterest_embedding from user_embedding), 1) > 0.125
    order by cost_per_view * (1 - (embedding <=> (
    select interest_embedding
    from user_embedding
  ))) desc
  limit 50
),
--with all the unique market_ids
unique_market_ids as (
  select distinct market_id
  from unredeemed_market_ads
),
--with the top ad for each unique market_id
top_market_ads as (
  select
    id, market_id, funds, cost_per_view
  from
    unredeemed_market_ads
  where
    market_id in (select market_id from unique_market_ids)
  order by
    cost_per_view * (1 - (embedding <=> (select interest_embedding from user_embedding))) desc
  limit
    50
)
select
  tma.id,
  tma.market_id,
  tma.funds,
  tma.cost_per_view,
  contracts.data
from
  top_market_ads as tma
  inner join contracts on contracts.id = tma.market_id
where
  contracts.resolution_time is null
  and contracts.visibility = 'public'
  and (contracts.close_time > now() or contracts.close_time is null)
$function$;

create
or replace function public.get_non_empty_private_message_channel_ids (
  p_user_id text,
  p_limit integer default null::integer
) returns table (id bigint) language plpgsql as $function$
BEGIN
    RETURN QUERY
    SELECT pumc.id
    FROM private_user_message_channels pumc
    JOIN private_user_message_channel_members pumcm ON pumcm.channel_id = pumc.id 
    WHERE pumcm.user_id = p_user_id
    AND EXISTS (
        SELECT 1 
        FROM private_user_messages
        WHERE pumc.id = private_user_messages.channel_id
    )
    ORDER BY pumc.last_updated_time DESC
    LIMIT p_limit;
END;
$function$;

create
or replace function public.get_non_empty_private_message_channel_ids (
  p_user_id text,
  p_ignored_statuses text[],
  p_limit integer
) returns setof private_user_message_channels language sql as $function$
select distinct pumc.*
from private_user_message_channels pumc
         join private_user_message_channel_members pumcm on pumcm.channel_id = pumc.id
         left join private_user_messages pum on pumc.id = pum.channel_id
    and (pum.visibility != 'introduction' or pum.user_id != p_user_id)
where pumcm.user_id = p_user_id
  and pumcm.status not in (select unnest(p_ignored_statuses))
  and pum.id is not null
order by pumc.last_updated_time desc
limit p_limit;
$function$;

create
or replace function public.get_noob_questions () returns setof contracts language sql as $function$with newbs as (
    select id
    from users
    where created_time > now() - interval '2 weeks'
  )
  select * from contracts
  where creator_id in (select * from newbs)
  and visibility = 'public'
  order by created_time desc$function$;

create
or replace function public.get_option_voters (this_contract_id text, this_option_id text) returns table (data json) language sql parallel SAFE as $function$
  SELECT users.data from users join votes on votes.user_id = users.id where votes.contract_id = this_contract_id and votes.id = this_option_id;
$function$;

create
or replace function public.get_rating (user_id text) returns table (count bigint, rating numeric) language sql immutable parallel SAFE as $function$
  WITH

  -- find average of each user's reviews
  avg_ratings AS (
    SELECT AVG(rating) AS avg_rating
    FROM reviews
    WHERE vendor_id = user_id
    GROUP BY reviewer_id
  ),

  total_count AS (
    SELECT COUNT(*) AS count
    FROM reviews
    WHERE vendor_id = user_id
  ),

  positive_counts AS (
    SELECT 5 + COUNT(*) AS count FROM avg_ratings WHERE avg_rating >= 4.0
  ),

  negative_counts AS (
    SELECT COUNT(*) AS count FROM avg_ratings WHERE avg_rating < 4.0
  ),

  -- calculate lower bound of 95th percentile confidence interval: https://www.evanmiller.org/how-not-to-sort-by-average-rating.html
  rating AS (
    SELECT (positive_counts.count + negative_counts.count) AS count,
       (
        (positive_counts.count + 1.9208) / (positive_counts.count + negative_counts.count) -
        1.96 * SQRT((positive_counts.count * negative_counts.count) / (positive_counts.count + negative_counts.count) + 0.9604) /
        (positive_counts.count + negative_counts.count)
      ) / (1 + 3.8416 / (positive_counts.count + negative_counts.count)) AS rating
    FROM positive_counts, negative_counts
  )

  SELECT total_count.count                               as count,
         -- squash with sigmoid, multiply by 5
         5 / (1 + POW(2.71828, -10*(rating.rating-0.5))) AS rating
  FROM total_count,rating;
$function$;

create
or replace function public.get_recently_active_contracts_in_group_slugs_1 (
  p_group_slugs text[],
  ignore_slugs text[],
  max integer
) returns table (data json, importance_score numeric) language sql stable parallel SAFE as $function$
select data, importance_score
from contracts
where
  visibility = 'public'
  and (group_slugs && p_group_slugs)
  and not (group_slugs && ignore_slugs)
order by last_updated_time desc
limit max
$function$;

create
or replace function public.get_top_market_ads (uid text, distance_threshold numeric) returns table (
  ad_id text,
  market_id text,
  ad_funds numeric,
  ad_cost_per_view numeric,
  market_data jsonb
) language sql parallel SAFE as $function$
--with all the redeemed ads (has a txn)
with redeemed_ad_ids as (
    select
            data->>'fromId' as fromId
    from
        txns
    where
                data->>'category' = 'MARKET_BOOST_REDEEM'
      and data->>'toId' = uid
),
-- with the user embedding
     user_embedding as (
         select interest_embedding, disinterest_embedding
         from user_embeddings
         where user_id = uid
     ),
--with all the ads that haven't been redeemed, by closest to your embedding
     unredeemed_market_ads as (
         select
             id, market_id, funds, cost_per_view, embedding
         from
             market_ads
         where
                 market_ads.user_id != uid -- hide your own ads; comment out to debug
           and not exists (
             SELECT 1
             FROM redeemed_ad_ids
             WHERE fromId = market_ads.id
         )
           and market_ads.funds >= cost_per_view
           and coalesce(embedding <=> (select disinterest_embedding from user_embedding), 1) > 0.125
           and (embedding <=> (select interest_embedding from user_embedding))  < distance_threshold
         order by cost_per_view * (1 - (embedding <=> (
             select interest_embedding
             from user_embedding
         ))) desc
         limit 50
     ),
--with all the unique market_ids
     unique_market_ids as (
         select distinct market_id
         from unredeemed_market_ads
     ),
--with the top ad for each unique market_id
     top_market_ads as (
         select
             id, market_id, funds, cost_per_view
         from
             unredeemed_market_ads
         where
                 market_id in (select market_id from unique_market_ids)
         order by
                 cost_per_view * (1 - (embedding <=> (select interest_embedding from user_embedding))) desc
         limit
             50
     )
select
    tma.id,
    tma.market_id,
    tma.funds,
    tma.cost_per_view,
    contracts.data
from
    top_market_ads as tma
        inner join contracts on contracts.id = tma.market_id
where
    contracts.resolution_time is null
  and (contracts.close_time > now() or contracts.close_time is null)
$function$;

create
or replace function public.get_user_bet_contracts (this_user_id text, this_limit integer) returns table (data json) language sql immutable parallel SAFE as $function$
  select c.data
  from contracts c
  join user_contract_metrics ucm on c.id = ucm.contract_id
  where ucm.user_id = this_user_id
  limit this_limit;
$function$;

create
or replace function public.get_user_group_id_for_current_user () returns text language plpgsql as $function$
DECLARE
    user_group_id text;
BEGIN
    SELECT group_id
    INTO user_group_id
    FROM group_members
    WHERE member_id = (auth.uid())::text;

    RETURN user_group_id;
END;
$function$;

create
or replace function public.get_user_manalink_claims (creator_id text) returns table (manalink_id text, claimant_id text, ts bigint) language sql as $function$
    select mc.manalink_id, (tx.data)->>'toId' as claimant_id, ((tx.data)->'createdTime')::bigint as ts
    from manalink_claims as mc
    join manalinks as m on mc.manalink_id = m.id
    join txns as tx on mc.txn_id = tx.id
    where m.creator_id = creator_id
$function$;

create
or replace function public.get_user_topic_interests_2 (p_user_id text) returns table (group_id text, score numeric) language plpgsql as $function$
begin
    return query
        select
            kv.key as group_id,
            coalesce((kv.value->>'conversionScore')::numeric, 0.0) as score
        from (
                 select group_ids_to_activity
                 from user_topic_interests
                 where user_id = p_user_id
                 order by created_time desc
                 limit 1
             ) as latest_record,
             jsonb_each(latest_record.group_ids_to_activity) as kv
        order by score desc;
end;
$function$;

create
or replace function public.get_your_contract_ids (uid text) returns table (contract_id text) language sql stable parallel SAFE as $function$ with your_liked_contracts as (
    select content_id as contract_id
    from user_reactions
    where user_id = uid
  ),
  your_followed_contracts as (
    select contract_id
    from contract_follows
    where follow_id = uid
  )
select contract_id
from your_liked_contracts
union
select contract_id
from your_followed_contracts $function$;

create
or replace function public.get_your_contract_ids (uid text, n integer, start integer) returns table (contract_id text) language sql immutable parallel SAFE as $function$
  with your_bet_on_contracts as (
    select contract_id
    from user_contract_metrics
    where user_id = uid
    and has_shares = true
  ), your_liked_contracts as (
    select content_id as contract_id
    from user_reactions
    where user_id = uid
  ), your_followed_contracts as (
    select contract_id
    from contract_follows
    where follow_id = uid
  )
  select contract_id from your_bet_on_contracts
  union
  select contract_id from your_liked_contracts
  union
  select contract_id from your_followed_contracts
  limit n
  offset start
$function$;

create
or replace function public.get_your_daily_changed_contracts (uid text, n integer, start integer) returns table (data jsonb, daily_score real) language sql stable parallel SAFE as $function$
select data,
  coalesce((data->>'dailyScore')::real, 0.0) as daily_score
from get_your_contract_ids(uid)
  left join contracts on contracts.id = contract_id
where contracts.outcome_type = 'BINARY'
order by daily_score desc
limit n offset start $function$;

create
or replace function public.get_your_recent_contracts (uid text, n integer, start integer) returns table (data jsonb, max_ts bigint) language sql stable parallel SAFE as $function$
  with your_bet_on_contracts as (
      select contract_id,
              (data->>'lastBetTime')::bigint as ts
      from user_contract_metrics
      where user_id = uid
        and ((data -> 'lastBetTime')::bigint) is not null
      order by ((data -> 'lastBetTime')::bigint) desc
      limit n * 10 + start * 5),
    your_liked_contracts as (
          select content_id as contract_id,
                public.ts_to_millis(created_time) as ts
          from user_reactions
          where user_id = uid
          order by created_time desc
          limit n * 10 + start * 5
    ),
    your_viewed_contracts as (
        select contract_id,
               public.ts_to_millis(last_page_view_ts) as ts
        from user_contract_views
        where user_id = uid and last_page_view_ts is not null
        order by last_page_view_ts desc
        limit n * 10 + start * 5
    ),
    recent_contract_ids as (
      select contract_id, ts
      from your_bet_on_contracts
      union all
      select contract_id, ts
      from your_viewed_contracts
      union all
      select contract_id, ts
      from your_liked_contracts
    ),
    recent_unique_contract_ids as (
      select contract_id, max(ts) AS max_ts
      from recent_contract_ids
      group by contract_id
    )
select data, max_ts
from recent_unique_contract_ids
left join contracts on contracts.id = contract_id
where data is not null
order by max_ts desc
limit n offset start $function$;

create
or replace function public.has_moderator_or_above_role (this_group_id text, this_user_id text) returns boolean language sql immutable parallel SAFE as $function$
select EXISTS (
        SELECT 1
        FROM group_members
        WHERE (
                group_id = this_group_id
                and member_id = this_user_id
                and (role='admin' or role='moderator')
            )
    ) $function$;

create
or replace function public.install_available_extensions_and_test () returns boolean language plpgsql as $function$
DECLARE extension_name TEXT;
allowed_extentions TEXT[] := string_to_array(current_setting('supautils.privileged_extensions'), ',');
BEGIN 
  FOREACH extension_name IN ARRAY allowed_extentions 
  LOOP
    SELECT trim(extension_name) INTO extension_name;
    /* skip below extensions check for now */
    CONTINUE WHEN extension_name = 'pgroonga' OR  extension_name = 'pgroonga_database' OR extension_name = 'pgsodium';
    CONTINUE WHEN extension_name = 'plpgsql' OR  extension_name = 'plpgsql_check' OR extension_name = 'pgtap';
    CONTINUE WHEN extension_name = 'supabase_vault' OR extension_name = 'wrappers';
    RAISE notice 'START TEST FOR: %', extension_name;
    EXECUTE format('DROP EXTENSION IF EXISTS %s CASCADE', quote_ident(extension_name));
    EXECUTE format('CREATE EXTENSION %s CASCADE', quote_ident(extension_name));
    RAISE notice 'END TEST FOR: %', extension_name;
  END LOOP;
    RAISE notice 'EXTENSION TESTS COMPLETED..';
    return true;
END;
$function$;

create
or replace function public.is_admin (input_string text) returns boolean language plpgsql immutable parallel SAFE as $function$
DECLARE
-- @Austin, @JamesGrugett, @SG, @DavidChee, @Alice, @ian, @IngaWei, @mqp, @Sinclair, @ManifoldPolitics, @baraki
    strings TEXT[] := ARRAY[
        'igi2zGXsfxYPgB0DJTXVJVmwCOr2',
        '5LZ4LgYuySdL1huCWe7bti02ghx2', 
        'tlmGNz9kjXc2EteizMORes4qvWl2', 
        'uglwf3YKOZNGjjEXKc5HampOFRE2', 
        'qJHrvvGfGsYiHZkGY6XjVfIMj233', 
        'AJwLWoo3xue32XIiAVrL5SyR1WB2', -- ian
        'GRwzCexe5PM6ThrSsodKZT9ziln2',
        '62TNqzdBx7X2q621HltsJm8UFht2', 
        '0k1suGSJKVUnHbCPEhHNpgZPkUP2',
        'vuI5upWB8yU00rP7yxj95J2zd952',
        'vUks7InCtYhBFrdLQhqXFUBHD4D2',
        'cA1JupYR5AR8btHUs2xvkui7jA93' -- Gen

        ];
BEGIN
    RETURN input_string = ANY(strings);
END;
$function$;

create
or replace function public.is_group_member (this_group_id text, this_user_id text) returns boolean language sql immutable parallel SAFE as $function$
select EXISTS (
        SELECT 1
        FROM group_members
        WHERE (
                group_id = this_group_id
                and member_id = this_user_id
            )
    ) $function$;

create
or replace function public.is_valid_contract (ct contracts) returns boolean language sql stable parallel SAFE as $function$
select ct.resolution_time is null
  and ct.visibility = 'public'
  and ((ct.close_time > now() + interval '10 minutes') or ct.close_time is null) $function$;

create
or replace function public.jsonb_array_to_text_array (_js jsonb) returns text[] language sql immutable parallel SAFE strict as $function$
select array(select jsonb_array_elements_text(_js))
$function$;

create
or replace function public.millis_interval (start_millis bigint, end_millis bigint) returns interval language sql immutable parallel SAFE as $function$
select millis_to_ts(end_millis) - millis_to_ts(start_millis)
$function$;

create
or replace function public.millis_to_ts (millis bigint) returns timestamp with time zone language sql immutable parallel SAFE as $function$
select to_timestamp(millis / 1000.0)
$function$;

create
or replace function public.pgrst_ddl_watch () returns event_trigger language plpgsql as $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $function$;

create
or replace function public.pgrst_drop_watch () returns event_trigger language plpgsql as $function$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $function$;

create
or replace function public.profit_leaderboard (limit_n integer) returns table (
  user_id text,
  profit numeric,
  name text,
  username text,
  avatar_url text
) language sql stable parallel SAFE as $function$
select p.user_id, coalesce(p.profit, p.balance + p.spice_balance + p.investment_value - p.total_deposits) as profit, u.name, u.username, u.data->>'avatarUrl' as avatar_url
from user_portfolio_history_latest p join users u on p.user_id = u.id
order by profit desc
limit limit_n
$function$;

create
or replace function public.profit_rank (
  uid text,
  excluded_ids text[] default array[]::text[]
) returns integer language sql stable parallel SAFE as $function$
select count(*) + 1
from user_portfolio_history_latest
where not user_id = any(excluded_ids)
  and coalesce(profit ,balance + spice_balance + investment_value - total_deposits) > (
    select coalesce(u.profit, balance + spice_balance + investment_value - total_deposits)
    from user_portfolio_history_latest u
    where u.user_id = uid
)
$function$;

create
or replace function public.random_alphanumeric (length integer) returns text language plpgsql as $function$
DECLARE
  result TEXT;
BEGIN
  WITH alphanum AS (
    SELECT ARRAY['0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
                 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'] AS chars
  )
  SELECT array_to_string(ARRAY (
    SELECT alphanum.chars[1 + floor(random() * 62)::integer]
    FROM alphanum, generate_series(1, length)
  ), '') INTO result;

  RETURN result;
END;
$function$;

create
or replace function public.recently_liked_contract_counts (since bigint) returns table (contract_id text, n integer) language sql stable parallel SAFE as $function$
select content_id as contract_id,
  count(*) as n
from user_reactions
where content_type = 'contract'
  and public.ts_to_millis(created_time) > since
group by contract_id $function$;

create
or replace function public.sample_resolved_bets (trader_threshold integer, p numeric) returns table (prob numeric, is_yes boolean) language sql stable parallel SAFE as $function$
select  0.5 * ((contract_bets.prob_before)::numeric + (contract_bets.prob_after)::numeric)  as prob, 
       ((contracts.resolution)::text = 'YES')::boolean as is_yes
from contract_bets
  join contracts on contracts.id = contract_bets.contract_id
where 
   contracts.outcome_type = 'BINARY'
  and (contracts.resolution = 'YES' or contracts.resolution = 'NO')
  and contracts.visibility = 'public'
  and (contracts.data->>'uniqueBettorCount')::int >= trader_threshold
  and amount > 0
  and random() < p
$function$;

create
or replace function public.save_user_topics_blank (p_user_id text) returns void language sql as $function$
with
    topic_embedding as (
        select avg(embedding) as average
        from topic_embeddings where topic not in (
            select unnest(ARRAY['destiny.gg', 'stock', 'planecrash', 'proofnik', 'permanent', 'personal']::text[])
        )
    )
insert into user_topics (user_id, topics, topic_embedding)
values (
           p_user_id,
           ARRAY['']::text[],
           (
               select average
               from topic_embedding
           )
       ) on conflict (user_id) do
    update set topics = excluded.topics,
               topic_embedding = excluded.topic_embedding;
$function$;

create
or replace function public.search_contract_embeddings (
  query_embedding vector,
  similarity_threshold double precision,
  match_count integer
) returns table (contract_id text, similarity double precision) language plpgsql as $function$ begin return query
    select contract_embeddings.contract_id as contract_id,
           1 - (
               contract_embeddings.embedding <=> query_embedding
               ) as similarity
    from contract_embeddings
    where 1 - (
        contract_embeddings.embedding <=> query_embedding
        ) > similarity_threshold
    order by contract_embeddings.embedding <=> query_embedding
    limit match_count;
end;
$function$;

create
or replace function public.test () returns void language plpgsql as $function$
BEGIN
       RAISE LOG 'Beginning Test: %', CURRENT_TIMESTAMP;
       NOTIFY pgrst, 'reload schema';
       RAISE LOG 'Ending Test: %', CURRENT_TIMESTAMP;
       EXCEPTION
        -- Handle exceptions here if needed
       WHEN others THEN
                RAISE EXCEPTION 'An error occurred: %', SQLERRM;
END;
$function$;

create
or replace function public.to_jsonb (jsonb) returns jsonb language sql immutable parallel SAFE strict as $function$ select $1 $function$;

create
or replace function public.ts_to_millis (ts timestamp with time zone) returns bigint language sql immutable parallel SAFE as $function$
select (extract(epoch from ts) * 1000)::bigint
$function$;

create
or replace function public.ts_to_millis (ts timestamp without time zone) returns bigint language sql immutable parallel SAFE as $function$
select extract(epoch from ts)::bigint * 1000
$function$;
