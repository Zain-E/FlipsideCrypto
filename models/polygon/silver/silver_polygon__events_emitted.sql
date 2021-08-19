{{ 
  config(
    materialized='incremental',
    unique_key='chain_id || block_id || tx_id || event_index', 
    incremental_strategy='delete+insert',
    cluster_by=['block_timestamp', 'block_id'],
    tags=['snowflake', 'polygon_silver', 'polygon_events_emitted','polygon']
  )
}}

select *
from {{ ref('polygon_dbt__events_emitted')}}
WHERE 1=1
{% if is_incremental() %}
        AND system_created_at >= (select dateadd('day',-1,max(system_created_at::date)) from {{source('silver_polygon', 'events_emitted')}})
{% endif %}
QUALIFY(row_number() over(partition by chain_id, block_id, tx_id, event_index order by system_created_at desc)) = 1