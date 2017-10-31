-- Your SQL goes here
CREATE OR REPLACE FUNCTION project_service._serialize_reward_basic_data(json)
 RETURNS json
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
        declare
            _result json;
        begin
            select json_build_object(
                'current_ip', ($1->>'current_ip')::text,
                'minimum_value', core_validator.raise_when_empty((($1->>'minimum_value')::decimal)::text, 'minimum_value')::decimal,
                'maximum_contributions', core_validator.raise_when_empty((($1->>'maximum_contributions')::integer)::text, 'maximum_contributions')::integer,
                'shipping_options', core_validator.raise_when_empty((($1->>'shipping_options')::project_service.shipping_options_enum)::text, 'shipping_options')::project_service.shipping_options_enum,
                'deliver_at', ($1->>'deliver_at')::date,
                'row_order',  ($1->>'row_order')::integer,
                'title', ($1->>'title')::text,
                'description', ($1->>'description')::text,
                'metadata', ($1->>'metadata')::json
            ) into _result;

            return _result;
        end;    
    $function$
;
---

CREATE OR REPLACE FUNCTION project_service._serialize_reward_basic_data(json, with_default json)
 RETURNS json
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
        declare
            _result json;
        begin
            select json_build_object(
                'current_ip', coalesce(($1->>'current_ip')::text, ($2->>'current_ip')),
                'minimum_value', core_validator.raise_when_empty(
                    coalesce((($1->>'minimum_value')::decimal)::text, ($2->>'minimum_value')::text), 'minimum_value')::decimal,
                'maximum_contributions', core_validator.raise_when_empty(
                    coalesce((($1->>'maximum_contributions')::integer)::text, ($2->>'maximum_contributions')::text), 'maximum_contributions')::integer,
                'shipping_options', core_validator.raise_when_empty(
                    coalesce((($1->>'shipping_options')::project_service.shipping_options_enum)::text, ($2->>'shipping_options')::text), 'shipping_options')::project_service.shipping_options_enum,
                'deliver_at', coalesce(($1->>'deliver_at')::date, ($2->>'deliver_at')::date),
                'row_order',  coalesce(($1->>'row_order')::integer, ($2->>'row_order')::integer),
                'title',  coalesce(($1->>'title')::text, ($2->>'title')::text),
                'description', coalesce(($1->>'description')::text, ($2->>'description')::text),
                'metadata', coalesce(($1->>'metadata')::json, ($2->>'metadata')::json)
            ) into _result;

            return _result;
        end;    
    $function$
;
CREATE OR REPLACE FUNCTION project_service_api.reward(data json)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
        declare
            _is_creating boolean default false;
            _result json;
            _reward project_service.rewards;
            _project project_service.projects;
            _version project_service.reward_versions;
            _refined jsonb;
            _created_at timestamp default now();
            _external_id text;
        begin
            -- ensure that roles come from any permitted
            perform core.force_any_of_roles('{platform_user, scoped_user}');
            
            -- check if have a id on request
            if ($1->>'id') is not null then
                select * from project_service.rewards
                    where id = ($1->>'id')::bigint
                    into _reward;
                    
                -- get project
                select * from project_service.projects
                    where id = _reward.project_id
                    into _project;
                
                if _reward.id is null or _project.id is null then
                    raise 'resource not found';
                end if;
            else
                _is_creating := true;
                -- get project
                select * from project_service.projects
                    where id = ($1->>'project_id')::bigint
                        and platform_id = core.current_platform_id()
                    into _project;
                -- check if project exists
                if _project.id is null then
                    raise 'project not found';
                end if;                    
            end if;

            -- check if project user is owner
            if not core.is_owner_or_admin(_project.user_id) then
                raise exception insufficient_privilege;
            end if;

            -- add some default data to refined
            _refined := jsonb_set(($1)::jsonb, '{current_ip}'::text[], to_jsonb(core.force_ip_address()::text));
            
            -- check if is creating or updating
            if _is_creating then
                _refined := jsonb_set(_refined, '{shipping_options}'::text[], to_jsonb(
                    coalesce(($1->>'shipping_options')::project_service.shipping_options_enum, 'free')::text
                ));
                _refined := jsonb_set(_refined, '{maximum_contributions}'::text[], to_jsonb(
                    coalesce(($1->>'maximum_contributions')::integer, 0)::text
                ));
                _refined := project_service._serialize_reward_basic_data(_refined::json)::jsonb;
                
                if current_role = 'platform_user' then
                    _external_id := ($1->>'external_id')::text;
                    _created_at := ($1->>'created_at')::timestamp;
                end if;
                
                -- insert new reward and version
                insert into project_service.rewards (platform_id, external_id, project_id, data, created_at)
                    values (_project.platform_id, _external_id, _project.id, _refined, _created_at)
                    returning * into _reward;
                insert into project_service.reward_versions(reward_id, data) 
                    values (_reward.id, row_to_json(_reward.*)::jsonb)
                    returning * into _version;                
            else
                _refined := project_service._serialize_reward_basic_data(_refined::json, _reward.data::json)::jsonb;
                -- insert new version and update reward
                insert into project_service.reward_versions(reward_id, data) 
                    values (_reward.id, row_to_json(_reward.*)::jsonb)
                    returning * into _version;
                update project_service.rewards
                    set data = _refined
                    where id = _reward.id
                    returning * into _reward;                
            end if;
            
            select json_build_object(
                'id', _reward.id,
                'old_version_id', _version.id,
                'data', _reward.data
            ) into _result;
            
            return _result;
        end;
    $function$
;