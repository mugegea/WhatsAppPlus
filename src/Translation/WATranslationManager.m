#import "WATranslationManager.h"
#import "../Common.h"
#import "../Settings/WATweakSettings.h"
#import <CommonCrypto/CommonDigest.h>
#import <NaturalLanguage/NaturalLanguage.h>

@interface WATranslationManager ()
@property (nonatomic, strong) NSCache<NSString *, NSString *> *translationCache;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightRequests;
// cacheKey -> [WATranslationDetailedCompletion]: coalesced waiters for the same request
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *pendingCompletions;
@property (nonatomic, strong) dispatch_queue_t syncQueue;
@end

@implementation WATranslationManager

+ (instancetype)sharedManager {
    static WATranslationManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WATranslationManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _translationCache = [[NSCache alloc] init];
        _translationCache.countLimit = 3000;

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 8.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        _inFlightRequests = [NSMutableSet set];
        _pendingCompletions = [NSMutableDictionary dictionary];
        _syncQueue = dispatch_queue_create("com.whatsappplus.translation.sync", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Cache & Helpers

static NSString *WAPercentEncode(NSString *string) {
    if (!string) return @"";
    NSMutableCharacterSet *set = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    // 显式剔除在 query value 里有歧义的字符（含 % 本体与 | 分隔符）
    [set removeCharactersInString:@":#[]@!$&'()*+,;=?/|%"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:set];
}

- (NSString *)cacheKeyForText:(NSString *)text targetLanguage:(NSString *)targetLang {
    NSString *combined = [NSString stringWithFormat:@"%@_%@", targetLang ?: @"", text ?: @""];
    const char *str = [combined UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", result[i]];
    }
    return hash;
}

- (nullable NSString *)cachedTranslationForText:(NSString *)text targetLanguage:(NSString *)targetLang {
    if (!text || text.length == 0) return nil;
    NSString *key = [self cacheKeyForText:text targetLanguage:targetLang];
    return [self.translationCache objectForKey:key];
}

- (NSString *)stringByDecodingHTMLEntities:(NSString *)string {
    if (!string || [string rangeOfString:@"&"].location == NSNotFound) return string;
    NSMutableString *result = [string mutableCopy];
    [result replaceOccurrencesOfString:@"&amp;" withString:@"&" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"&#39;" withString:@"'" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"&apos;" withString:@"'" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"&lt;" withString:@"<" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"&gt;" withString:@">" options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    return result;
}

#pragma mark - Language Detection

- (nullable NSString *)detectedLanguageCodeForText:(NSString *)text {
    if (!text || text.length == 0) return nil;
    if (@available(iOS 12.0, *)) {
        NLLanguageRecognizer *recognizer = [[NLLanguageRecognizer alloc] init];
        [recognizer processString:text];
        NLLanguage dominant = recognizer.dominantLanguage;
        if (!dominant) return nil;
        // 归一化中文变体
        if ([dominant isEqualToString:NLLanguageSimplifiedChinese]) return @"zh-CN";
        if ([dominant isEqualToString:NLLanguageTraditionalChinese]) return @"zh-TW";
        return (NSString *)dominant;
    }
    return nil;
}

- (NSString *)sourceLanguageCodeForText:(NSString *)text targetLanguage:(NSString *)targetLang {
    NSString *detected = [self detectedLanguageCodeForText:text];
    if (detected.length > 0 && ![self languageCode:detected matchesTarget:targetLang]) {
        return detected;
    }
    // 启发式兜底：目标是中文则假设源为英文，反之假设源为中文
    return [targetLang hasPrefix:@"zh"] ? @"en" : @"zh-CN";
}

- (NSString *)effectiveIncomingTargetForText:(NSString *)text configuredTarget:(NSString *)target {
    NSString *t = target.length > 0 ? target : @"zh-CN";
    NSString *detected = [self detectedLanguageCodeForText:text];
    if (detected.length > 0 && [self languageCode:detected matchesTarget:t]) {
        // 源语言与目标相同：翻译为"另一"语言，保证双语显示（中文<->英语）
        if ([t hasPrefix:@"zh"]) return @"en";
        if ([t hasPrefix:@"en"]) return @"zh-CN";
    }
    return t;
}

- (BOOL)languageCode:(NSString *)code matchesTarget:(NSString *)target {
    if (!code.length || !target.length) return NO;
    BOOL codeIsZh = [code hasPrefix:@"zh"];
    BOOL targetIsZh = [target hasPrefix:@"zh"];
    if (codeIsZh && targetIsZh) return YES;   // zh-CN / zh-TW / zh-Hans 互认
    if (codeIsZh != targetIsZh) return NO;
    return [code isEqualToString:target] || [code hasPrefix:target] || [target hasPrefix:code];
}

- (BOOL)isText:(NSString *)text alreadyInLanguage:(NSString *)targetLang {
    if (!text || text.length == 0) return YES;
    if (!targetLang || targetLang.length == 0) return NO;
    NSString *detected = [self detectedLanguageCodeForText:text];
    if (!detected) return NO; // 无法判断时不跳过，宁可多翻一次
    return [self languageCode:detected matchesTarget:targetLang];
}

#pragma mark - Formatting

- (NSString *)formatIncomingMessageWithOriginal:(NSString *)originalText
                                    translation:(NSString *)translatedText {
    if (!translatedText || translatedText.length == 0) return originalText ?: @"";
    if (!originalText || originalText.length == 0) return translatedText;
    if ([translatedText isEqualToString:originalText]) return originalText;
    if ([originalText containsString:translatedText]) return originalText;
    // 原文在上，译文在下
    return [NSString stringWithFormat:@"%@\n──────────\n🌐 %@", originalText, translatedText];
}

- (NSString *)formatBilingualTextWithTranslation:(NSString *)translatedText
                                    originalText:(NSString *)originalText {
    if (!translatedText || translatedText.length == 0) return originalText ?: @"";
    if (!originalText || originalText.length == 0) return translatedText;
    if ([translatedText isEqualToString:originalText]) return originalText;

    return [NSString stringWithFormat:@"%@\n──────────────\n%@", translatedText, originalText];
}

#pragma mark - Translation Entrypoint

- (void)translateText:(NSString *)text
       targetLanguage:(NSString *)targetLang
           completion:(WATranslationCompletion)completion {
    [self translateText:text targetLanguage:targetLang detailedCompletion:^(NSString * _Nullable translatedText, NSString * _Nullable detectedSourceLang, NSError * _Nullable error) {
        if (completion) {
            completion(translatedText, error);
        }
    }];
}

- (void)translateText:(NSString *)text
       targetLanguage:(NSString *)targetLang
   detailedCompletion:(WATranslationDetailedCompletion)completion {
    if (!text || text.length == 0) {
        if (completion) completion(@"", nil, nil);
        return;
    }

    NSString *target = targetLang.length > 0 ? targetLang : @"zh-CN";

    // 智能跳过：已经是目标语言就不请求
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    if (settings.autoSkipSameLanguage && [self isText:text alreadyInLanguage:target]) {
        WALog(@"[Translation] Skipping: text already in target language (%@)", target);
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(text, target, nil);
            });
        }
        return;
    }

    NSString *cacheKey = [self cacheKeyForText:text targetLanguage:target];
    NSString *cached = [self.translationCache objectForKey:cacheKey];
    if (cached) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached, nil, nil);
            });
        }
        return;
    }

    // 相同请求合并：后来者排队，等 in-flight 的那次完成后一起回调，不再吞回调
    __block BOOL alreadyRunning = NO;
    dispatch_sync(self.syncQueue, ^{
        if ([self.inFlightRequests containsObject:cacheKey]) {
            alreadyRunning = YES;
            if (completion) {
                NSMutableArray *list = self.pendingCompletions[cacheKey];
                if (!list) {
                    list = [NSMutableArray array];
                    self.pendingCompletions[cacheKey] = list;
                }
                [list addObject:[completion copy]];
            }
        } else {
            [self.inFlightRequests addObject:cacheKey];
        }
    });
    if (alreadyRunning) {
        return;
    }

    // 唯一收口：清 in-flight 标记、分发排队的回调、统一回主线程
    WATranslationDetailedCompletion wrapped = ^(NSString * _Nullable t, NSString * _Nullable l, NSError * _Nullable e) {
        [self finishRequestForKey:cacheKey translatedText:t detectedSourceLang:l error:e primary:completion];
    };

    // Engine chain: Google Cloud (if key) -> Google Free RPC -> MyMemory
    BOOL useGoogleCloud = (settings.translationEngine == WATranslationEngineGoogleCloud) && (settings.googleCloudApiKey.length > 0);

    if (useGoogleCloud) {
        [self executeGoogleCloudTranslation:text targetLanguage:target apiKey:settings.googleCloudApiKey cacheKey:cacheKey completion:^(NSString * _Nullable translatedText, NSString * _Nullable detectedSourceLang, NSError * _Nullable error) {
            if (error || !translatedText || translatedText.length == 0) {
                WALog(@"[Translation] Google Cloud failed, trying Google Free RPC...");
                [self executeGoogleFreeRPCTranslation:text targetLanguage:target cacheKey:cacheKey completion:wrapped];
            } else {
                wrapped(translatedText, detectedSourceLang, nil);
            }
        }];
    } else {
        [self executeGoogleFreeRPCTranslation:text targetLanguage:target cacheKey:cacheKey completion:wrapped];
    }
}

/**
 * 链路终点：所有引擎最终都走这里。只调用一次。
 */
- (void)finishRequestForKey:(NSString *)cacheKey
             translatedText:(NSString * _Nullable)translatedText
          detectedSourceLang:(NSString * _Nullable)detectedLang
                      error:(NSError * _Nullable)error
                    primary:(WATranslationDetailedCompletion _Nullable)primary {
    __block NSArray *pending = nil;
    dispatch_sync(self.syncQueue, ^{
        [self.inFlightRequests removeObject:cacheKey];
        pending = [self.pendingCompletions[cacheKey] copy] ?: @[];
        [self.pendingCompletions removeObjectForKey:cacheKey];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        if (primary) primary(translatedText, detectedLang, error);
        for (WATranslationDetailedCompletion cb in pending) {
            cb(translatedText, detectedLang, error);
        }
    });
}

#pragma mark - Engine 1: Google Cloud Translation API v2

- (void)executeGoogleCloudTranslation:(NSString *)text
                       targetLanguage:(NSString *)target
                               apiKey:(NSString *)apiKey
                             cacheKey:(NSString *)cacheKey
                           completion:(WATranslationDetailedCompletion)completion {
    NSString *urlString = [NSString stringWithFormat:@"https://translation.googleapis.com/language/translate/v2?key=%@", WAPercentEncode(apiKey)];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil, nil, [NSError errorWithDomain:@"WATranslationErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid Google Cloud URL"}]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    NSString *googleTarget = target;
    if ([target isEqualToString:@"zh-CN"]) googleTarget = @"zh";

    NSDictionary *payload = @{
        @"q": @[text],
        @"target": googleTarget,
        @"format": @"text"
    };

    NSError *serializeError = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serializeError];
    if (serializeError) {
        if (completion) completion(nil, nil, serializeError);
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || !data) {
            if (completion) completion(nil, nil, error);
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![json isKindOfClass:[NSDictionary class]] || json[@"error"]) {
            if (completion) completion(nil, nil, jsonError ?: [NSError errorWithDomain:@"WATranslationError" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Cloud API response error"}]);
            return;
        }

        NSArray *translations = json[@"data"][@"translations"];
        if (translations && [translations isKindOfClass:[NSArray class]] && translations.count > 0) {
            NSDictionary *item = translations[0];
            NSString *rawTranslated = item[@"translatedText"];
            NSString *detectedLang = item[@"detectedSourceLanguage"];

            NSString *finalTranslated = [self stringByDecodingHTMLEntities:rawTranslated];
            if (finalTranslated.length > 0) {
                [self.translationCache setObject:finalTranslated forKey:cacheKey];
            }
            if (completion) completion(finalTranslated, detectedLang, nil);
        } else {
            if (completion) completion(nil, nil, [NSError errorWithDomain:@"WATranslationError" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Empty translation data"}]);
        }
    }];
    [task resume];
}

#pragma mark - Engine 2: Google Free Public RPC

- (void)executeGoogleFreeRPCTranslation:(NSString *)text
                         targetLanguage:(NSString *)target
                               cacheKey:(NSString *)cacheKey
                             completion:(WATranslationDetailedCompletion)completion {
    NSString *encodedText = WAPercentEncode(text);
    NSString *urlString = [NSString stringWithFormat:@"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=%@&dt=t&q=%@", target, encodedText];

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil, nil, [NSError errorWithDomain:@"WATranslationErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 15_3_1 like Mac OS X) AppleWebKit/605.1.15" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || !data) {
            WALog(@"Google Free RPC error (%@), falling back to MyMemory...", error.localizedDescription);
            [self executeMyMemoryTranslation:text targetLanguage:target cacheKey:cacheKey completion:completion];
            return;
        }

        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![json isKindOfClass:[NSArray class]]) {
            WALog(@"Google Free JSON error, falling back to MyMemory...");
            [self executeMyMemoryTranslation:text targetLanguage:target cacheKey:cacheKey completion:completion];
            return;
        }

        NSArray *rootArray = (NSArray *)json;
        NSString *detectedLang = nil;
        if (rootArray.count > 2 && [rootArray[2] isKindOfClass:[NSString class]]) {
            detectedLang = rootArray[2];
        }

        if (rootArray.count > 0 && [rootArray[0] isKindOfClass:[NSArray class]]) {
            NSArray *sentences = rootArray[0];
            NSMutableString *resultString = [NSMutableString string];
            for (id item in sentences) {
                if ([item isKindOfClass:[NSArray class]] && [(NSArray *)item count] > 0) {
                    NSString *part = item[0];
                    if ([part isKindOfClass:[NSString class]]) {
                        [resultString appendString:part];
                    }
                }
            }

            NSString *finalTranslated = [self stringByDecodingHTMLEntities:[resultString copy]];
            if (finalTranslated.length > 0) {
                [self.translationCache setObject:finalTranslated forKey:cacheKey];
            }
            if (completion) completion(finalTranslated, detectedLang, nil);
        } else {
            [self executeMyMemoryTranslation:text targetLanguage:target cacheKey:cacheKey completion:completion];
        }
    }];
    [task resume];
}

#pragma mark - Engine 3: MyMemory Free Translation API (fallback)

- (void)executeMyMemoryTranslation:(NSString *)text
                    targetLanguage:(NSString *)target
                          cacheKey:(NSString *)cacheKey
                        completion:(WATranslationDetailedCompletion)completion {
    // MyMemory 不支持 sl=auto，必须给显式源语言
    NSString *srcCode = [self sourceLanguageCodeForText:text targetLanguage:target];
    NSString *langpair = [NSString stringWithFormat:@"%@|%@", srcCode, target];
    NSString *encodedText = WAPercentEncode(text);
    NSString *urlString = [NSString stringWithFormat:@"https://api.mymemory.translated.net/get?q=%@&langpair=%@",
                           encodedText, WAPercentEncode(langpair)];

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil, nil, [NSError errorWithDomain:@"WATranslationError" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Invalid MyMemory URL"}]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 15_3_1)" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || !data) {
            if (completion) completion(nil, nil, error);
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        // 必须校验 responseStatus==200：失败时 translatedText 里装的是错误文本，不能当翻译用
        // 注意成功时是数字 200，失败时是字符串 "403"，integerValue 两种都兼容
        long status = [json[@"responseStatus"] integerValue];
        if (!jsonError && [json isKindOfClass:[NSDictionary class]] && status == 200) {
            NSString *translated = json[@"responseData"][@"translatedText"];
            if (translated && [translated isKindOfClass:[NSString class]] && translated.length > 0) {
                NSString *finalTranslated = [self stringByDecodingHTMLEntities:translated];
                [self.translationCache setObject:finalTranslated forKey:cacheKey];
                if (completion) completion(finalTranslated, srcCode, nil);
                return;
            }
        }

        if (completion) {
            completion(nil, nil, jsonError ?: [NSError errorWithDomain:@"WATranslationError" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"All translation engines failed"}]);
        }
    }];
    [task resume];
}

- (void)clearCache {
    [self.translationCache removeAllObjects];
}

@end
