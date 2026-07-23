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

require_handler() {
  local handler="$1"
  local expected="$2"
  local body

  body="$(handler_body "${handler}")"
  if ! grep -Fqx -- "${expected}" <<<"${body}"; then
    printf 'FAIL: %s contract is missing: %s\n' "${handler}" "${expected}" >&2
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
require_handler 'OnBuyBulletTopic' '    uint16_t buy_bullet_num = 0;'
require_handler 'OnBuyBulletTopic' '        referee_->AddNeedBullet(buy_bullet_num) == LibXR::ErrorCode::OK) {'
require_handler_count 'OnBuyBulletTopic' 'AddNeedBullet('
require_handler 'OnRemoteBuyBulletTopic' '    uint8_t remote_buy_bullet_request = 0;'
require_handler 'OnRemoteBuyBulletTopic' '        remote_buy_bullet_request != 0U && referee_ != nullptr &&'
require_handler 'OnRemoteBuyBulletTopic' '        referee_->RequestRemoteBulletExchange() == LibXR::ErrorCode::OK) {'
require_handler_count 'OnRemoteBuyBulletTopic' 'RequestRemoteBulletExchange('
require_handler 'OnRemoteBuyHpTopic' '    uint8_t buy_hp = 0;'
require_handler 'OnRemoteBuyHpTopic' '    if (ReadTopicData(raw_data, buy_hp) && buy_hp != 0 && referee_ != nullptr) {'
require_handler 'OnRemoteBuyHpTopic' '      referee_->SetHPRemote();'
require_handler_count 'OnRemoteBuyHpTopic' 'SetHPRemote('

# Resurrection and switch mode are level values, including false and zero.
require_handler 'OnBuyResurrectionTopic' '    bool buy_resurrection = false;'
require_handler 'OnBuyResurrectionTopic' '      referee_->SetRevivalRemote(buy_resurrection);'
require_handler_count 'OnBuyResurrectionTopic' 'SetRevivalRemote('
require_handler 'OnStateTopic' '    uint8_t state = 0;'
require_handler 'OnStateTopic' '      referee_->SetSwitchMode(static_cast<State>(state));'
require_handler_count 'OnStateTopic' 'SetSwitchMode('

printf 'PASS: SentryProtocol decision topic semantics are locked.\n'
