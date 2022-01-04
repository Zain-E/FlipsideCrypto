{{ config(
  materialized = 'incremental',
  unique_key = '_unique_key',
  incremental_strategy = 'merge',
  tags = ['snowflake', 'algorand', 'transactions', 'silver_algorand_tx']
) }}

WITH outerTXN AS (

  SELECT
    intra,
    b.round AS block_id,
    txn :txn :grp :: STRING AS tx_group_id,
    txid :: text AS tx_id,
    'false' AS inner_tx,
    CASE
      WHEN txn :txn :type :: STRING = 'appl' THEN NULL
      ELSE asset
    END AS asset_id,
    txn :txn :snd :: text AS sender,
    txn :txn :fee / pow(
      10,
      6
    ) AS fee,
    txn :txn :type :: STRING AS tx_type,
    txn :txn :gh :: STRING AS genisis_hash,
    txn AS tx_message,
    extra,
    _FIVETRAN_SYNCED
  FROM
    {{ source(
      'algorand',
      'TXN'
    ) }}
    b
),
innerTXN AS(
  SELECT
    intra,
    b.round AS block_id,
    txn :txn :grp :: STRING AS tx_group_id,
    txid :: text AS tx_id,
    'true' AS inner_tx,
    CASE
      WHEN flat.value :txn :type :: STRING = 'pay' THEN 0
      WHEN flat.value :txn :type :: STRING = 'acfg' THEN NULL
      WHEN flat.value :txn :type :: STRING = 'axfer' THEN flat.value :txn :xaid
      ELSE asset
    END AS asset_id,
    flat.value :txn :snd :: text AS sender,
    flat.value :txn :fee / pow(
      10,
      6
    ) AS fee,
    flat.value :txn :type :: STRING AS tx_type,
    txn :txn :gh :: STRING AS genisis_hash,
    flat.value :txn AS tx_message,
    extra,
    _FIVETRAN_SYNCED
  FROM
    {{ source(
      'algorand',
      'TXN'
    ) }}
    b,
    LATERAL FLATTEN(
      input => txn :dt :itx
    ) flat
  WHERE
    txn :dt :itx IS NOT NULL
),
all_txn AS (
  SELECT
    *
  FROM
    outerTXN
  UNION ALL
  SELECT
    *
  FROM
    innerTXN
)
SELECT
  intra,
  block_id,
  tx_group_id,
  HEX_DECODE_STRING(
    tx_id
  ) AS tx_id,
  TO_BOOLEAN(inner_tx) AS inner_tx,
  asset_id,
  algorand_decode_b64_addr(
    sender
  ) AS sender,
  fee,
  csv.type AS tx_type,
  csv.name AS tx_type_name,
  genisis_hash,
  tx_message,
  extra,
  concat_ws(
    '-',
    block_id :: STRING,
    intra :: STRING
  ) AS _unique_key,
  _FIVETRAN_SYNCED
FROM
  all_txn b
  LEFT JOIN {{ ref('silver_algorand__transaction_types') }}
  csv
  ON b.tx_type = csv.type
WHERE
  1 = 1

{% if is_incremental() %}
AND _FIVETRAN_SYNCED >= (
  SELECT
    MAX(
      _FIVETRAN_SYNCED
    )
  FROM
    {{ this }}
)
{% endif %}
