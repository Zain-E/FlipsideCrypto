{{ config(
    materialized = 'incremental',
    unique_key = 'block_id || tx_id',
    incremental_strategy = 'delete+insert',
    cluster_by = ['block_timestamp', 'block_id'],
    tags=['snowflake', 'terra', 'mirror', 'collateral']
) }}


WITH prices AS (

  SELECT 
      date_trunc('hour', block_timestamp) as hour,
      currency,
      symbol,
      avg(price_usd) as price
    FROM {{ ref('terra__oracle_prices')}} 
    
    WHERE 1=1
    
    {% if is_incremental() %}
    AND block_timestamp::date >= (select max(block_timestamp::date) from {{ref('silver_terra__msgs')}})
    {% endif %}

    GROUP BY 1,2,3

), 

msgs AS(

SELECT
  m.blockchain,
  chain_id,
  block_id,
  block_timestamp,
  tx_id,
  msg_value:execute_msg:open_position:collateral_ratio as collateral_ratio,
  msg_value:sender::string as sender,
  msg_value:contract::string as contract_address,
  l.address_name as contract_label
FROM {{ref('silver_terra__msgs')}} m

LEFT OUTER JOIN {{source('shared','udm_address_labels_new')}} as l
ON msg_value:contract::string = l.address

WHERE msg_value:contract::string = 'terra1wfz7h3aqf4cjmjcvc6s8lxdhh7k30nkczyf0mj' -- Mirror Mint Contract
  AND msg_value:execute_msg:open_position IS NOT NULL
  AND tx_status = 'SUCCEEDED'

  {% if is_incremental() %}
    AND block_timestamp::date >= (select max(block_timestamp::date) from {{ref('silver_terra__msgs')}})
  {% endif %}

),
   
events AS(

SELECT
  tx_id,
  event_attributes:position_idx as collateral_id,
  event_attributes:collateral_amount[0]:amount/ POW(10,6) as collateral_amount,
  collateral_amount * o.price AS collateral_amount_usd,
  event_attributes:collateral_amount[0]:denom::string as collateral_currency,
  event_attributes:mint_amount[0]:amount/ POW(10,6) as mint_amount,
  mint_amount * i.price AS mint_amount_usd,
  event_attributes:mint_amount[0]:denom::string as mint_currency
FROM {{ref('silver_terra__msg_events')}} t

LEFT OUTER JOIN prices o
 ON date_trunc('hour', t.block_timestamp) = o.hour
 AND t.event_attributes:collateral_amount[0]:denom::string = o.currency 

LEFT OUTER JOIN prices i
 ON date_trunc('hour', t.block_timestamp) = i.hour
 AND t.event_attributes:mint_amount[0]:denom::string = i.currency  

WHERE t.event_attributes:is_short::string = 'false'
  AND tx_id IN(SELECT DISTINCT tx_id FROM msgs)
  AND event_type = 'from_contract'

  {% if is_incremental() %}
    AND block_timestamp::date >= (select max(block_timestamp::date) from {{ref('silver_terra__msgs')}})
  {% endif %}

)

SELECT
  blockchain,
  chain_id,
  block_id,
  block_timestamp,
  m.tx_id,
  collateral_id,
  collateral_ratio,
  sender,
  collateral_amount,
  collateral_amount_usd,
  collateral_currency,
  mint_amount,
  mint_amount_usd,
  mint_currency,
  contract_address,
  contract_label
FROM msgs m

JOIN events e 
  ON m.tx_id = e.tx_id