{{ 
  config(
    materialized='incremental', 
    sort='block_timestamp', 
    unique_key='block_id', 
    incremental_strategy='delete+insert',
    cluster_by=['block_timestamp'],
    tags=['snowflake', 'terra', 'grant']
  )
}}

SELECT 
  blockchain,
  chain_id,
  tx_status,
  block_id,
  block_timestamp, 
  tx_id, 
  msg_type, 
  REGEXP_REPLACE(msg_value:grantee,'\"','') as grantee,
  REGEXP_REPLACE(msg_value:msgs[0]:type,'\"','') as type,
  REGEXP_REPLACE(msg_value:msgs[0]:value:amount[0]:amount,'\"','') as amount,
  REGEXP_REPLACE(msg_value:msgs[0]:value:amount[0]:denom,'\"','') as currency,
  REGEXP_REPLACE(msg_value:msgs[0]:value:from_address,'\"','') as event_from,
  REGEXP_REPLACE(msg_value:msgs[0]:value:to_address,'\"','') as event_to
  
FROM {{source('silver_terra', 'msgs')}} 
WHERE msg_module = 'msgauth'
  AND msg_type = 'msgauth/MsgExecAuthorized'
{% if is_incremental() %}
 AND block_timestamp >= getdate() - interval '1 days'
{% else %}
 AND block_timestamp >= getdate() - interval '9 months'
{% endif %}