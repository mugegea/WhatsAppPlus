#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WATranslationEngine) {
    WATranslationEngineGoogleCloud = 0, // 官方 Google Cloud Translation API (需配置 Key)
    WATranslationEngineGoogleFree = 1   // 免费 Google 公共接口 (免 Key)，失败自动降级 MyMemory
};

/**
 * Per-chat auto-translate entry stored in NSUserDefaults.
 * Key: chat JID (e.g. "12345@s.whatsapp.net" or "12345-67890@g.us")
 * Value: @{ @"name": NSString, @"enabled": NSNumber(BOOL), @"updatedAt": NSNumber(NSTimeInterval) }
 */
typedef NSDictionary<NSString *, NSDictionary *> WAChatTranslateMap;

@interface WATweakSettings : NSObject


// Translation Settings
@property (nonatomic, assign) BOOL autoTranslateIncoming;   // 总开关：关闭则所有聊天都不自动翻译
@property (nonatomic, assign) BOOL autoTranslateOutgoing;  // 发送时自动翻译：输入原文，点发送自动转为双语发出
@property (nonatomic, assign) BOOL bilingualOutgoing;
@property (nonatomic, assign) BOOL autoSkipSameLanguage;
@property (nonatomic, copy) NSString *targetLanguage;          // 接收目标语言
@property (nonatomic, copy) NSString *outgoingTargetLanguage;  // 发送目标语言
@property (nonatomic, assign) WATranslationEngine translationEngine;
@property (nonatomic, copy) NSString *googleCloudApiKey;

// 当前正在显示的聊天（transient，不持久化，由 Tweak.x 在 viewDidAppear/Disappear 维护）
@property (nonatomic, copy, nullable) NSString *currentChatJID;
@property (nonatomic, copy, nullable) NSString *currentChatName;


@property (nonatomic, assign) BOOL liquidGlassEnabled;

+ (instancetype)sharedSettings;
- (void)save;

// Helpers for languages
+ (NSDictionary<NSString *, NSString *> *)supportedLanguages;

#pragma mark - Per-Chat Auto-Translate

/**
 * 综合判断：总开关 && (该聊天的显式设置 ?: 新聊天默认策略)
 */
- (BOOL)shouldAutoTranslateChatJID:(nullable NSString *)jid;

/** 该聊天是否有显式设置；有则通过 outEnabled 返回 */
- (BOOL)hasExplicitSettingForChatJID:(NSString *)jid enabled:(BOOL * _Nullable)outEnabled;

/** 设置/更新某聊天的自动翻译开关 */
- (void)setAutoTranslate:(BOOL)enabled forChatJID:(NSString *)jid chatName:(nullable NSString *)name;

/** 删除某聊天的显式设置（恢复为默认策略） */
- (void)removeAutoTranslateForChatJID:(NSString *)jid;

/** 全部显式设置，按 updatedAt 降序排列的 JID 数组 */
- (NSArray<NSString *> *)allPerChatJIDsSorted;

/** 某 JID 的显式设置条目（name/enabled/updatedAt），无则返回 nil */
- (nullable NSDictionary *)perChatEntryForJID:(NSString *)jid;

@end

NS_ASSUME_NONNULL_END
