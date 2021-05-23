{{ 
  config(
    materialized='view', 
    tags=['snowflake', 'thorchain', 'add_events']
  )
}}

SELECT
  to_timestamp(e.BLOCK_TIMESTAMP/1000000000) as block_timestamp,
  bl.height as block_id,
  e.TX as tx_id,
  e.RUNE_E8,
  e.CHAIN as blockchain,
  e.ASSET_E8,
  e.POOL as pool_name,
  e.MEMO,
  e.TO_ADDR as to_address,
  e.FROM_ADDR	as from_address,
  e.ASSET
FROM {{source('thorchain_midgard', 'add_events')}} e
INNER JOIN {{source('thorchain_midgard', 'block_log')}} bl ON bl.timestamp = e.BLOCK_TIMESTAMP