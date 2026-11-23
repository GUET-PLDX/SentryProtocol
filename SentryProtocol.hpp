#pragma once

// clang-format off
/* === MODULE MANIFEST V2 ===
module_description: 哨兵裁判系统决策发送模块
depends:
- id: GUET-PLDX/Referee
  ref: 4eb967e28d76bfb3004ddb03a565b10741f1d888
=== END MANIFEST === */
// clang-format on

#include <atomic>
#include <cstdint>

#include "Referee.hpp"
#include "libxr.hpp"
#include "libxr_def.hpp"
#include "message.hpp"

class SentryProtocol {
 public:
  using State = Referee::State;

  SentryProtocol(
      Referee* referee, const char* referee_sentry_tp_name = "robot_game_ref",
      const char* buy_bullet_topic_name = "sentry_buy_bullet_num",
      const char* remote_buy_bullet_times_topic_name =
          "sentry_remote_buy_bullet_times",
      const char* remote_buy_hp_times_topic_name = "sentry_remote_buy_hp_times",
      const char* buy_resurrection_topic_name = "sentry_buy_resurrection",
      const char* state_topic_name = "sentry_state")
      : referee_(referee),
        referee_suber_(referee_sentry_tp_name),
        buy_bullet_topic_(
            LibXR::Topic::CreateTopic<uint16_t>(buy_bullet_topic_name)),
        remote_buy_bullet_times_topic_(LibXR::Topic::CreateTopic<uint8_t>(
            remote_buy_bullet_times_topic_name)),
        remote_buy_hp_times_topic_(
            LibXR::Topic::CreateTopic<uint8_t>(remote_buy_hp_times_topic_name)),
        buy_resurrection_topic_(
            LibXR::Topic::CreateTopic<bool>(buy_resurrection_topic_name)),
        state_topic_(LibXR::Topic::CreateTopic<uint8_t>(state_topic_name)) {
    RegisterTopic<uint16_t, &SentryProtocol::OnBuyBulletTopic>(
        buy_bullet_topic_);
    RegisterTopic<uint8_t, &SentryProtocol::OnRemoteBuyBulletTopic>(
        remote_buy_bullet_times_topic_);
    RegisterTopic<uint8_t, &SentryProtocol::OnRemoteBuyHpTopic>(
        remote_buy_hp_times_topic_);
    RegisterTopic<bool, &SentryProtocol::OnBuyResurrectionTopic>(
        buy_resurrection_topic_);
    RegisterTopic<uint8_t, &SentryProtocol::OnStateTopic>(state_topic_);

    referee_suber_.StartWaiting();
  }

  void SetSwitchMode(State state) {
    if (referee_ == nullptr) {
      return;
    }

    const auto result = referee_->SetSwitchMode(state);
    RecordResult(result);
    if (result == LibXR::ErrorCode::OK)
      RecordResult(referee_->SendSentryPack());
  }

  LibXR::ErrorCode GetLastRequestError() const {
    return last_request_error_.load();
  }
  uint32_t GetRejectedRequests() const { return rejected_requests_.load(); }

  void OnMonitor() {
    if (referee_suber_.Available()) {
      referee_pack_ = referee_suber_.GetData();
      referee_suber_.StartWaiting();
    }

    if (referee_ == nullptr) {
      return;
    }

    const bool fresh =
        referee_pack_.referee_online &&
        (referee_pack_.source_fresh_mask & Referee::SOURCE_ROBOT_STATUS) != 0U;
    const bool is_dead = fresh && referee_pack_.robot_status.max_hp != 0U &&
                         referee_pack_.robot_status.remain_hp == 0U;
    referee_->SetConfirmRevival(is_dead);
    if (is_dead) RecordResult(referee_->SendSentryPack());
  }

 private:
  void RecordResult(LibXR::ErrorCode result) {
    last_request_error_ = result;
    if (result != LibXR::ErrorCode::OK) ++rejected_requests_;
  }
  /* Data 必须与主题创建时的负载类型一致，否则 RegisterCallback 会断言 */
  template <typename Data, void (SentryProtocol::*HANDLER)(const Data&)>
  void RegisterTopic(LibXR::Topic& topic) {
    auto callback = LibXR::Topic::Callback::Create(
        [](bool in_isr, SentryProtocol* self, const Data& data) {
          UNUSED(in_isr);
          (self->*HANDLER)(data);
        },
        this);
    topic.RegisterCallback(callback);
  }

  void OnBuyBulletTopic(const uint16_t& buy_bullet_num) {
    if (referee_ == nullptr) return;
    const auto result = referee_->AddNeedBullet(buy_bullet_num);
    RecordResult(result);
    if (result == LibXR::ErrorCode::OK)
      RecordResult(referee_->SendSentryPack());
  }

  void OnRemoteBuyBulletTopic(const uint8_t& remote_buy_bullet_request) {
    if (remote_buy_bullet_request == 0U || referee_ == nullptr) return;
    const auto result = referee_->RequestRemoteBulletExchange();
    RecordResult(result);
    if (result == LibXR::ErrorCode::OK)
      RecordResult(referee_->SendSentryPack());
  }

  void OnRemoteBuyHpTopic(const uint8_t& buy_hp) {
    if (buy_hp != 0 && referee_ != nullptr) {
      const auto result = referee_->SetHPRemote();
      RecordResult(result);
      if (result == LibXR::ErrorCode::OK)
        RecordResult(referee_->SendSentryPack());
    }
  }

  void OnBuyResurrectionTopic(const bool& buy_resurrection) {
    if (referee_ != nullptr) {
      referee_->SetRevivalRemote(buy_resurrection);
      RecordResult(referee_->SendSentryPack());
    }
  }

  void OnStateTopic(const uint8_t& state) {
    if (referee_ != nullptr) {
      SetSwitchMode(static_cast<State>(state));
    }
  }

  Referee::RobotGameRefereePack referee_pack_{};
  std::atomic<LibXR::ErrorCode> last_request_error_{LibXR::ErrorCode::OK};
  std::atomic<uint32_t> rejected_requests_{0};

  Referee* referee_;
  LibXR::Topic::ASyncSubscriber<Referee::RobotGameRefereePack> referee_suber_;
  LibXR::Topic buy_bullet_topic_;
  LibXR::Topic remote_buy_bullet_times_topic_;
  LibXR::Topic remote_buy_hp_times_topic_;
  LibXR::Topic buy_resurrection_topic_;
  LibXR::Topic state_topic_;
};
