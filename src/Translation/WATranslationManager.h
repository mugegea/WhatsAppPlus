#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WATranslationCompletion)(NSString * _Nullable translatedText, NSError * _Nullable error);
typedef void (^WATranslationDetailedCompletion)(NSString * _Nullable translatedText, NSString * _Nullable detectedSourceLang, NSError * _Nullable error);

@interface WATranslationManager : NSObject

+ (instancetype)sharedManager;

/**
 * Check if translation is cached for the given text and target language.
 */
- (nullable NSString *)cachedTranslationForText:(NSString *)text targetLanguage:(NSString *)targetLang;

/**
 * Check if text is already in the specified language to avoid redundant translations.
 */
- (BOOL)isText:(NSString *)text alreadyInLanguage:(NSString *)targetLang;

/**
 * Detect the most likely language code of the text (normalized: zh-Hans -> zh-CN).
 * Returns nil when detection is inconclusive.
 */
- (nullable NSString *)detectedLanguageCodeForText:(NSString *)text;

/**
 * Best-effort source language code for engines that require an explicit
 * source (e.g. MyMemory). Never returns nil; falls back to a heuristic
 * based on the target language.
 */
- (NSString *)sourceLanguageCodeForText:(NSString *)text targetLanguage:(NSString *)targetLang;

/**
 * 计算接收消息的实际目标语言：源语言自动识别；若源语言与配置目标相同，
 * 则翻译为"另一"语言（中文<->英语），保证双语显示。
 */
- (NSString *)effectiveIncomingTargetForText:(NSString *)text configuredTarget:(NSString *)target;

/**
 * Asynchronously translates text to target language.
 * Engine chain: Google Cloud (if key) -> Google Free RPC -> MyMemory.
 * Concurrent identical requests are coalesced: every caller gets a callback.
 * Completion is always delivered on the main thread.
 */
- (void)translateText:(NSString *)text
       targetLanguage:(NSString *)targetLang
           completion:(WATranslationCompletion)completion;

/**
 * Detailed translation with detected source language.
 */
- (void)translateText:(NSString *)text
       targetLanguage:(NSString *)targetLang
   detailedCompletion:(WATranslationDetailedCompletion)completion;

/**
 * Formats an incoming message: original text on top, translation below.
 */
- (NSString *)formatIncomingMessageWithOriginal:(NSString *)originalText
                                    translation:(NSString *)translatedText;

/**
 * Formats a clean bilingual message (Translated Foreign Text + Original Native Text).
 */
- (NSString *)formatBilingualTextWithTranslation:(NSString *)translatedText
                                    originalText:(NSString *)originalText;

/**
 * Clear cached translations.
 */
- (void)clearCache;

@end

NS_ASSUME_NONNULL_END
