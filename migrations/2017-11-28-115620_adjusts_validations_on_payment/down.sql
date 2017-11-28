-- This file should undo anything in `up.sql`
CREATE OR REPLACE FUNCTION payment_service._serialize_payment_basic_data(json)
 RETURNS json
 LANGUAGE plpgsql
 STABLE
AS $function$
        declare
            _result json;
        begin
            select json_build_object(
                'current_ip', core_validator.raise_when_empty(($1->>'current_ip')::text, 'ip_address')::text,
                'anonymous', core_validator.raise_when_empty(($1->>'anonymous')::text, 'anonymous')::boolean,
                'amount', core_validator.raise_when_empty((($1->>'amount')::decimal)::text, 'amount')::decimal,
                'payment_method', core_validator.raise_when_empty(lower(($1->>'payment_method')::text), 'payment_method'),
                'customer', json_build_object(
                    'name', core_validator.raise_when_empty(($1->'customer'->>'name')::text, 'name'),
                    'email', core_validator.raise_when_empty(($1->'customer'->>'email')::text, 'email'),
                    'document_number', core_validator.raise_when_empty(($1->'customer'->>'document_number')::text, 'document_number'),
                    'address', json_build_object(
                        'street', core_validator.raise_when_empty(($1->'customer'->'address'->>'street')::text, 'street'),
                        'street_number', core_validator.raise_when_empty(($1->'customer'->'address'->>'street_number')::text, 'street_number'),
                        'neighborhood', core_validator.raise_when_empty(($1->'customer'->'address'->>'neighborhood')::text, 'neighborhood'),
                        'zipcode', core_validator.raise_when_empty(($1->'customer'->'address'->>'zipcode')::text, 'zipcode'),
                        'country', core_validator.raise_when_empty(($1->'customer'->'address'->>'country')::text, 'country'),
                        'state', core_validator.raise_when_empty(($1->'customer'->'address'->>'state')::text, 'state'),
                        'city', core_validator.raise_when_empty(($1->'customer'->'address'->>'city')::text, 'city'),
                        'complementary', ($1->'customer'->'address'->>'complementary')::text
                    ),
                    'phone', json_build_object(
                        'ddi', core_validator.raise_when_empty(($1->'customer'->'phone'->>'ddi')::text, 'phone_ddi'),
                        'ddd', core_validator.raise_when_empty(($1->'customer'->'phone'->>'ddd')::text, 'phone_ddd'),
                        'number', core_validator.raise_when_empty(($1->'customer'->'phone'->>'number')::text, 'phone_number')
                    )
                )
            ) into _result;

            return _result;
        end;
    $function$
;