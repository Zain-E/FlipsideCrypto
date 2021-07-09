{{ 
  config(
    materialized='incremental', 
    sort='block_timestamp', 
    unique_key='block_id', 
    incremental_strategy='delete+insert',
    cluster_by=['block_timestamp'],
    tags=['snowflake', 'terra', 'voting_power']
  )
}}

SELECT
  block_number AS block_id, 
  block_timestamp,
  blockchain,
  address,
  voting_power
FROM {{source('terra', 'terra_validator_voting_power')}}
WHERE
{% if is_incremental() %}
  block_timestamp >= getdate() - interval '1 days'
{% else %}
  block_timestamp >= getdate() - interval '9 months'
{% endif %}