{{ 
  config(
    materialized='incremental', 
    sort='block_timestamp', 
    unique_key='block_id', 
    incremental_strategy='delete+insert',
    cluster_by=['block_timestamp'],
    tags=['snowflake', 'terra', 'staking']
  )
}}

WITH staking_events AS (
  SELECT 
    blockchain,
    chain_id,
    tx_status,
    block_id,
    block_timestamp, 
    tx_id, 
    tx_type,
    msg_module,
    msg_type, 
    msg_index,
    event_type,
    event_attributes,
    event_attributes:validator::string AS validator,
    event_attributes:completion_time::string AS completion_time,
    -- event_attributes:amount / POW(10,6) AS unbond_amount,
    event_attributes:"0_sender"::string AS "0_sender",
    event_attributes:"1_sender"::string AS "1_sender",
    event_attributes:"2_sender"::string AS "2_sender",
    event_attributes:action::string AS action,
    event_attributes:module::string AS module,
    event_attributes:"0_amount"[0]:amount / POW(10,6) AS event_transfer_0_amount,
    event_attributes:"0_amount"[0]:denom::string AS event_transfer_0_currency,
    event_attributes:"0_recipient"::string AS event_transfer_0_recipient,
    event_attributes:"0_sender"::string AS event_transfer_0_sender,
    event_attributes:"1_amount"[0]:amount / POW(10,6) AS event_transfer_1_amount,
    event_attributes:"1_amount"[0]:denom::string AS event_transfer_1_currency,
    event_attributes:"1_recipient"::string AS event_transfer_1_recipient,
    event_attributes:"1_sender"::string AS event_transfer_1_sender
  FROM {{source('silver_terra', 'msg_events')}} 
  WHERE msg_module = 'staking' 
    AND msg_type = 'staking/MsgUndelegate'
    AND tx_status = 'SUCCEEDED'
    {% if is_incremental() %}
    AND block_timestamp >= getdate() - interval '1 days'
    {% else %}
    AND block_timestamp >= getdate() - interval '9 months'
    {% endif %}
),
staking AS (
  SELECT 
    blockchain,
    chain_id,
    tx_status,
    block_id,
    block_timestamp, 
    tx_id, 
    msg_type, 
    REGEXP_REPLACE(msg_value:delegator_address,'\"','') as delegator_address,
    REGEXP_REPLACE(msg_value:validator_address,'\"','') as validator_address,
    REGEXP_REPLACE(msg_value:amount:amount,'\"','') as event_amount,
    REGEXP_REPLACE(msg_value:amount:denom,'\"','') as event_currency
  FROM {{source('silver_terra', 'msgs')}}  
  WHERE msg_module = 'staking' 
    AND msg_type = 'staking/MsgUndelegate'
    AND tx_status = 'SUCCEEDED'
    {% if is_incremental() %}
    AND block_timestamp >= getdate() - interval '1 days'
    {% else %}
    AND block_timestamp >= getdate() - interval '9 months'
    {% endif %}
), 

event_base AS (
  SELECT DISTINCT
    blockchain,
    chain_id,
    tx_status,
    block_id,
    block_timestamp, 
    tx_id, 
    msg_type
  FROM staking 
), 

message AS (
  SELECT
    tx_id, 
    action,
    module,
    "0_sender",
    "1_sender",
    "2_sender"
  FROM staking_events 
  WHERE event_type = 'message' AND msg_index = 0
), 

transfer AS (
  SELECT
    tx_id, 
    event_transfer_0_amount,
    event_transfer_0_currency,
    event_transfer_0_recipient,
    event_transfer_0_sender,
    event_transfer_1_amount,
    event_transfer_1_currency,
    event_transfer_1_recipient,
    event_transfer_1_sender
  FROM staking_events 
  WHERE event_type = 'transfer' AND msg_index = 0
),

unbond AS (
  SELECT
    tx_id,
    -- unbond_amount,
    validator,
    completion_time
  FROM staking_events 
  WHERE event_type = 'unbond' 
)


SELECT
  event_base.blockchain,
  event_base.chain_id,
  event_base.tx_status,
  event_base.block_id,
  event_base.block_timestamp, 
  event_base.tx_id, 
  event_base.msg_type, 
  action,
  module,
  "0_sender",
  "1_sender",
  "2_sender",
  event_transfer_0_amount,
  event_transfer_0_currency,
  event_transfer_0_recipient,
  event_transfer_0_sender,
  event_transfer_1_amount,
  event_transfer_1_currency,
  event_transfer_1_recipient,
  event_transfer_1_sender,
  staking.event_amount,
  staking.event_currency,
  -- unbond_amount,
  validator,
  completion_time,
  staking.delegator_address,
  staking.validator_address
FROM event_base
LEFT JOIN message
ON event_base.tx_id = message.tx_id
LEFT JOIN transfer
ON event_base.tx_id = transfer.tx_id
LEFT JOIN unbond
ON event_base.tx_id = unbond.tx_id
LEFT JOIN staking
ON event_base.tx_id = staking.tx_id