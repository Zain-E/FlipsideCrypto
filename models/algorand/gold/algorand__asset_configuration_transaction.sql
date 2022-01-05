{{ config(
    materialized = 'view',
    tags = ['snowflake', 'algorand_views', 'asset_configuration_transaction', 'gold'],
) }}

SELECT
    intra,
    block_id,
    tx_group_id,
    tx_id,
    asset_id,
    asset_supply,
    sender,
    fee,
    asset_paramaters,
    tx_type,
    tx_type_name,
    genisis_hash,
    tx_message,
    extra
FROM
    {{ ref('silver_algorand__asset_configuration_transaction') }}