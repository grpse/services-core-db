-- This file should undo anything in `up.sql`
CREATE OR REPLACE FUNCTION payment_service_api.create_payment(data json)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
        declare
            _result json;
            _payment payment_service.catalog_payments;
            _user_id bigint;
            _user community_service.users;
            _project project_service.projects;
            _subscription payment_service.subscriptions;
            _refined jsonb;
        begin
            -- check roles to define how user_id is set
            if current_role = 'platform_user' or current_role = 'admin' then
                _user_id := ($1 ->> 'user_id')::bigint;
            else
                _user_id := core.current_user_id();
            end if;
            
            -- check if project exists on platform
            if ($1->>'project_id') is null 
                OR not core.project_exists_on_platform(($1->>'project_id')::bigint, core.current_platform_id()) then
                raise exception 'project not found on platform';
            end if;

            -- check if user exists on current platform
            if _user_id is null or not core.user_exists_on_platform(_user_id, core.current_platform_id()) then
                raise exception 'missing user';
            end if;
            
            -- set user into variable
            select * 
            from community_service.users 
            where id = _user_id
            into _user;
            
            -- fill ip address to received params
            select jsonb_set(($1)::jsonb, '{current_ip}'::text[], to_jsonb(current_setting('request.header.x-forwarded-for', true)::text))
                into _refined;
            
            -- if user already has filled document_number/name/email should use then
            if not core_validator.is_empty((_user.data->>'name')::text) then
                select jsonb_set(_refined, '{customer,name}', to_jsonb(_user.data->>'name'::text))
                    into _refined;
            end if;
            
            if not core_validator.is_empty((_user.data->>'email')::text) then
                select jsonb_set(_refined, '{customer,email}', to_jsonb(_user.data->>'email'::text))
                    into _refined;
            end if;
            
            if not core_validator.is_empty((_user.data->>'email')::text) then
                select jsonb_set(_refined, '{customer,document_number}', to_jsonb(_user.data->>'document_number'::text))
                    into _refined;                
            end if;
            
            -- generate a base structure to payment json
            select (payment_service.check_and_generate_payment_data((_refined)::json))::jsonb
                into _refined;
                
            -- insert payment in table
            insert into payment_service.catalog_payments (
                platform_id, project_id, user_id, data, gateway
            ) values (
                core.current_platform_id(),
                ($1->>'project_id')::bigint,
                _user_id,
                _refined,
                coalesce(($1->>'gateway')::text, 'pagarme')
            ) returning * into _payment;

            -- check if payment is a subscription to create one
            if ($1->>'subscription')::boolean then
                insert into payment_service.subscriptions (
                    platform_id, project_id, user_id
                ) values (_payment.platform_id, _payment.project_id, _payment.user_id)
                returning * into _subscription;

                update payment_service.catalog_payments
                    set subscription_id = _subscription.id
                    where id = _payment.id;
            end if;

            -- build result json with payment_id and subscription_id
            select json_build_object(
                'id', _payment.id,
                'subscription_id', _subscription.id
            ) into _result;

            -- notify to backend processor via listen
            PERFORM pg_notify('process_payments_channel', _result::text);

            return _result;
        end;
    $function$;