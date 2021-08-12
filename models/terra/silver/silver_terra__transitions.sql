{{ 
  config(
    materialized='incremental',
    unique_key='chain_id || block_id || index || transition_type || event', 
    incremental_strategy='delete+insert',
    cluster_by=['block_timestamp', 'block_id'],
    tags=['snowflake', 'terra_silver', 'terra_transitions']
  )
}}

select *
from {{ ref('terra_dbt__transitions')}}
WHERE 1=1
{% if is_incremental() %}
        AND system_created_at::date >= (select dateadd('day',-1,max(system_created_at::date)) from {{source('silver_terra', 'transitions')}})
{% endif %}
QUALIFY(row_number() over(partition by chain_id, block_id, index, transition_type, event order by system_created_at desc)) = 1
