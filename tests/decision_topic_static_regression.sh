#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="${1:-${MODULE_DIR}/SentryProtocol.hpp}"

if [[ ! -f "${SOURCE_FILE}" ]]; then
  printf 'FAIL: source file not found: %s\n' "${SOURCE_FILE}" >&2
  exit 1
fi

require_source() {
  local expected="$1"

  if ! tr -d '\r' <"${SOURCE_FILE}" | tr '\n\t' ' ' | sed 's/  */ /g' | \
    grep -Fq -- "${expected}"; then
    printf 'FAIL: missing source contract: %s\n' "${expected}" >&2
    exit 1
  fi
}

handler_body() {
  local handler="$1"

  tr -d '\r' <"${SOURCE_FILE}" | \
    awk "/  void ${handler}\\(const LibXR::ConstRawData& raw_data\\) \\{/,/^  \\}/"
}

normalized_handler() {
  local handler="$1"

  handler_body "${handler}" | tr '\n\t' ' ' | sed 's/  */ /g'
}

require_handler_structure() {
  local handler="$1"
  local expected="$2"

  if ! normalized_handler "${handler}" | grep -Fq -- "${expected}"; then
    printf 'FAIL: %s must retain handler structure: %s\n' "${handler}" \
      "${expected}" >&2
    exit 1
  fi
}

require_handler_count() {
  local handler="$1"
  local expected="$2"
  local count

  count="$(handler_body "${handler}" | grep -Fc -- "${expected}" || true)"
  if [[ "${count}" != "1" ]]; then
    printf 'FAIL: %s must contain exactly one %s call (found %s)\n' \
      "${handler}" "${expected}" "${count}" >&2
    exit 1
  fi
}

# Topics retain their established producer payload types.
require_source 'buy_bullet_topic_( LibXR::Topic::CreateTopic<uint16_t>(buy_bullet_topic_name)),'
require_source 'remote_buy_bullet_times_topic_(LibXR::Topic::CreateTopic<uint8_t>( remote_buy_bullet_times_topic_name)),'
require_source 'remote_buy_hp_times_topic_( LibXR::Topic::CreateTopic<uint8_t>(remote_buy_hp_times_topic_name)),'
require_source 'buy_resurrection_topic_( LibXR::Topic::CreateTopic<bool>(buy_resurrection_topic_name)),'
require_source 'state_topic_(LibXR::Topic::CreateTopic<uint8_t>(state_topic_name)) {'

# A bullet quantity is a delta; every nonzero remote counter is one request.
require_handler_structure 'OnBuyBulletTopic' \
  'uint16_t buy_bullet_num = 0; if (ReadTopicData(raw_data, buy_bullet_num) && referee_ != nullptr && referee_->AddNeedBullet(buy_bullet_num) == LibXR::ErrorCode::OK) { referee_->SendSentryPack(); }'
require_handler_count 'OnBuyBulletTopic' 'AddNeedBullet('
require_handler_structure 'OnRemoteBuyBulletTopic' \
  'uint8_t remote_buy_bullet_request = 0; if (ReadTopicData(raw_data, remote_buy_bullet_request) && remote_buy_bullet_request != 0U && referee_ != nullptr && referee_->RequestRemoteBulletExchange() == LibXR::ErrorCode::OK) { referee_->SendSentryPack(); }'
require_handler_count 'OnRemoteBuyBulletTopic' 'RequestRemoteBulletExchange('
require_handler_structure 'OnRemoteBuyHpTopic' \
  'uint8_t buy_hp = 0; if (ReadTopicData(raw_data, buy_hp) && buy_hp != 0 && referee_ != nullptr) { referee_->SetHPRemote(); referee_->SendSentryPack(); }'
require_handler_count 'OnRemoteBuyHpTopic' 'SetHPRemote('

# Resurrection and switch mode are level values, including false and zero.
require_handler_structure 'OnBuyResurrectionTopic' \
  'bool buy_resurrection = false; if (ReadTopicData(raw_data, buy_resurrection) && referee_ != nullptr) { referee_->SetRevivalRemote(buy_resurrection); referee_->SendSentryPack(); }'
require_handler_count 'OnBuyResurrectionTopic' 'SetRevivalRemote('
require_handler_structure 'OnStateTopic' \
  'uint8_t state = 0; if (ReadTopicData(raw_data, state) && referee_ != nullptr) { referee_->SetSwitchMode(static_cast<State>(state)); referee_->SendSentryPack(); }'
require_handler_count 'OnStateTopic' 'SetSwitchMode('

printf 'PASS: SentryProtocol decision topic semantics are locked.\n'
