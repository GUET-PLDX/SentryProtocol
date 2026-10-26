#pragma once

// clang-format off
/* === MODULE MANIFEST V2 ===
module_description: 哨兵裁判系统决策发送模块
depends:
- id: GUET-PLDX/Referee
=== END MANIFEST === */
// clang-format on

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

    referee_->SetSwitchMode(state);
    referee_->SendSentryPack();
  }

  void OnMonitor() {
    if (referee_suber_.Available()) {
      referee_pack_ = referee_suber_.GetData();
      referee_suber_.StartWaiting();
    }

    if (referee_ == nullptr) {
      return;
    }

    const bool IS_DEAD = referee_pack_.robot_status.max_hp != 0 &&
                         referee_pack_.robot_status.remain_hp == 0;
    if (IS_DEAD) {
      referee_->SetConfirmRevival(true);
      referee_->SendSentryPack();
    }
  }

 private:
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
    if (referee_ != nullptr &&
        referee_->AddNeedBullet(buy_bullet_num) == LibXR::ErrorCode::OK) {
      referee_->SendSentryPack();
    }
  }

  void OnRemoteBuyBulletTopic(const uint8_t& remote_buy_bullet_request) {
    if (remote_buy_bullet_request != 0U && referee_ != nullptr &&
        referee_->RequestRemoteBulletExchange() == LibXR::ErrorCode::OK) {
      referee_->SendSentryPack();
    }
  }

  void OnRemoteBuyHpTopic(const uint8_t& buy_hp) {
    if (buy_hp != 0 && referee_ != nullptr) {
      referee_->SetHPRemote();
      referee_->SendSentryPack();
    }
  }

  void OnBuyResurrectionTopic(const bool& buy_resurrection) {
    if (referee_ != nullptr) {
      referee_->SetRevivalRemote(buy_resurrection);
      referee_->SendSentryPack();
    }
  }

  void OnStateTopic(const uint8_t& state) {
    if (referee_ != nullptr) {
      referee_->SetSwitchMode(static_cast<State>(state));
      referee_->SendSentryPack();
    }
  }

  Referee* referee_;
  LibXR::Topic::ASyncSubscriber<Referee::RobotGameRefereePack> referee_suber_;
  LibXR::Topic buy_bullet_topic_;
  LibXR::Topic remote_buy_bullet_times_topic_;
  LibXR::Topic remote_buy_hp_times_topic_;
  LibXR::Topic buy_resurrection_topic_;
  LibXR::Topic state_topic_;

  Referee::RobotGameRefereePack referee_pack_{};
};
