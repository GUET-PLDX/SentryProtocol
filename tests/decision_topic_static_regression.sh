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

  tr -d '\r' <"${SOURCE_FILE}" | awk -v handler="${handler}" '
    !in_handler && index($0, "void " handler "(const LibXR::ConstRawData& raw_data) {") {
      in_handler = 1
    }
    in_handler {
      print
      open_line = $0
      close_line = $0
      depth += gsub(/{/, "", open_line) - gsub(/}/, "", close_line)
      if (depth == 0) {
        exit
      }
    }
  '
}

normalized_handler() {
  local handler="$1"

  handler_body "${handler}" | tr '\n\t' ' ' | \
    sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

require_handler_structure() {
  local handler="$1"
  local expected="$2"
  local actual

  actual="$(normalized_handler "${handler}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL: %s handler structure changed\n' "${handler}" >&2
    printf 'expected: %s\n' "${expected}" >&2
    printf 'actual: %s\n' "${actual}" >&2
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

# Every handler is compared in full after whitespace normalization. This rejects
# extra statements and gates around otherwise-valid predicate/API fragments.
require_handler_structure 'OnBuyBulletTopic' \
  'void OnBuyBulletTopic(const LibXR::ConstRawData& raw_data) { uint16_t buy_bullet_num = 0; if (ReadTopicData(raw_data, buy_bullet_num) && referee_ != nullptr && referee_->AddNeedBullet(buy_bullet_num) == LibXR::ErrorCode::OK) { referee_->SendSentryPack(); } }'
require_handler_count 'OnBuyBulletTopic' 'AddNeedBullet('
require_handler_structure 'OnRemoteBuyBulletTopic' \
  'void OnRemoteBuyBulletTopic(const LibXR::ConstRawData& raw_data) { uint8_t remote_buy_bullet_request = 0; if (ReadTopicData(raw_data, remote_buy_bullet_request) && remote_buy_bullet_request != 0U && referee_ != nullptr && referee_->RequestRemoteBulletExchange() == LibXR::ErrorCode::OK) { referee_->SendSentryPack(); } }'
require_handler_count 'OnRemoteBuyBulletTopic' 'RequestRemoteBulletExchange('
require_handler_structure 'OnRemoteBuyHpTopic' \
  'void OnRemoteBuyHpTopic(const LibXR::ConstRawData& raw_data) { uint8_t buy_hp = 0; if (ReadTopicData(raw_data, buy_hp) && buy_hp != 0 && referee_ != nullptr) { referee_->SetHPRemote(); referee_->SendSentryPack(); } }'
require_handler_count 'OnRemoteBuyHpTopic' 'SetHPRemote('
require_handler_structure 'OnBuyResurrectionTopic' \
  'void OnBuyResurrectionTopic(const LibXR::ConstRawData& raw_data) { bool buy_resurrection = false; if (ReadTopicData(raw_data, buy_resurrection) && referee_ != nullptr) { referee_->SetRevivalRemote(buy_resurrection); referee_->SendSentryPack(); } }'
require_handler_count 'OnBuyResurrectionTopic' 'SetRevivalRemote('
require_handler_structure 'OnStateTopic' \
  'void OnStateTopic(const LibXR::ConstRawData& raw_data) { uint8_t state = 0; if (ReadTopicData(raw_data, state) && referee_ != nullptr) { referee_->SetSwitchMode(static_cast<State>(state)); referee_->SendSentryPack(); } }'
require_handler_count 'OnStateTopic' 'SetSwitchMode('

write_remote_bullet_moved_mutation() {
  local output_file="$1"

  tr -d '\r' <"${SOURCE_FILE}" | awk '
    /void OnRemoteBuyBulletTopic\(const LibXR::ConstRawData& raw_data\) \{/ {
      in_handler = 1
    }
    in_handler {
      sub(/referee_->RequestRemoteBulletExchange\(\) == LibXR::ErrorCode::OK/, "true")
    }
    {
      print
    }
    in_handler && !moved && $0 == "    }" {
      print "    referee_->RequestRemoteBulletExchange();"
      moved = 1
    }
    in_handler && $0 == "  }" {
      in_handler = 0
    }
  ' >"${output_file}"
}

write_remote_hp_moved_mutation() {
  local output_file="$1"

  tr -d '\r' <"${SOURCE_FILE}" | awk '
    /void OnRemoteBuyHpTopic\(const LibXR::ConstRawData& raw_data\) \{/ {
      in_handler = 1
    }
    in_handler {
      sub(/^[[:space:]]*referee_->SetHPRemote\(\);/, "")
    }
    {
      print
    }
    in_handler && !moved && $0 == "    }" {
      print "    referee_->SetHPRemote();"
      moved = 1
    }
    in_handler && $0 == "  }" {
      in_handler = 0
    }
  ' >"${output_file}"
}

write_resurrection_gate_mutation() {
  local output_file="$1"

  tr -d '\r' <"${SOURCE_FILE}" | awk '
    /void OnBuyResurrectionTopic\(const LibXR::ConstRawData& raw_data\) \{/ {
      in_handler = 1
    }
    in_handler && !added_gate && $0 == "    if (ReadTopicData(raw_data, buy_resurrection) && referee_ != nullptr) {" {
      print "    if (buy_resurrection) {"
      added_gate = 1
    }
    in_handler && $0 == "  }" {
      print "    }"
      print
      in_handler = 0
      next
    }
    {
      print
    }
  ' >"${output_file}"
}

write_state_gate_mutation() {
  local output_file="$1"

  tr -d '\r' <"${SOURCE_FILE}" | awk '
    /void OnStateTopic\(const LibXR::ConstRawData& raw_data\) \{/ {
      in_handler = 1
    }
    in_handler && !added_gate && $0 == "    if (ReadTopicData(raw_data, state) && referee_ != nullptr) {" {
      print "    if (state != 0U) {"
      added_gate = 1
    }
    in_handler && $0 == "  }" {
      print "    }"
      print
      in_handler = 0
      next
    }
    {
      print
    }
  ' >"${output_file}"
}

expect_mutation_rejected() {
  local name="$1"
  local source_file="$2"
  local output

  if output="$(SENTRY_PROTOCOL_SKIP_MUTATIONS=1 bash "${BASH_SOURCE[0]}" "${source_file}" 2>&1)"; then
    printf 'FAIL: mutation unexpectedly passed: %s\n' "${name}" >&2
    return 1
  fi

  printf 'PASS: mutation rejected: %s (%s)\n' "${name}" \
    "${output%%$'\n'*}"
}

run_mutation_suite() {
  local mutation_dir

  mutation_dir="$(mktemp -d "${TMPDIR:-/tmp}/sentry-topic-contract.XXXXXX")"
  write_remote_bullet_moved_mutation "${mutation_dir}/remote_bullet_moved.hpp"
  write_remote_hp_moved_mutation "${mutation_dir}/remote_hp_moved.hpp"
  write_resurrection_gate_mutation "${mutation_dir}/resurrection_gated.hpp"
  write_state_gate_mutation "${mutation_dir}/state_gated.hpp"

  expect_mutation_rejected 'remote bullet request moved out of if' \
    "${mutation_dir}/remote_bullet_moved.hpp"
  expect_mutation_rejected 'remote HP request moved out of if' \
    "${mutation_dir}/remote_hp_moved.hpp"
  expect_mutation_rejected 'resurrection true gate' \
    "${mutation_dir}/resurrection_gated.hpp"
  expect_mutation_rejected 'state nonzero gate' \
    "${mutation_dir}/state_gated.hpp"
  rm -rf "${mutation_dir}"
}

if [[ "${SENTRY_PROTOCOL_SKIP_MUTATIONS:-0}" != '1' ]]; then
  run_mutation_suite
fi

printf 'PASS: SentryProtocol decision topic semantics are locked.\n'
