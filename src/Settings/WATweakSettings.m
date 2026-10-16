#import "WATweakSettings.h"
#import "../Common.h"

static NSString *const kAutoTranslateIncoming = @"WATweak_AutoTranslateIncoming";
static NSString *const kAutoTranslateOutgoing = @"WATweak_AutoTranslateOutgoing";
static NSString *const kPerChatTranslate = @"WATweak_PerChatTranslate";
static NSString *const kBilingualOutgoing = @"WATweak_BilingualOutgoing";
static NSString *const kAutoSkipSameLanguage = @"WATweak_AutoSkipSameLanguage";
static NSString *const kTargetLanguage = @"WATweak_TargetLanguage";
static NSString *const kOutgoingTargetLanguage = @"WATweak_OutgoingTargetLanguage";
static NSString *const kTranslationEngine = @"WATweak_TranslationEngine";
static NSString *const kGoogleCloudApiKey = @"WATweak_GoogleCloudApiKey";
static NSString *const kLiquidGlassEnabled = @"WATweak_LiquidGlassEnabled";

// 上限：防止 per-chat 表无限增长
static const NSUInteger kMaxPerChatEntries = 500;

@implementation WATweakSettings

+ (instancetype)sharedSettings {
    static WATweakSettings *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WATweakSettings alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        // Register default values (only on first launch)
        if ([defaults objectForKey:kAutoTranslateIncoming] == nil) {
            _autoTranslateIncoming = YES;   // 总开关默认开
            _autoTranslateOutgoing = YES;   // 发送时自动翻译默认开：输入一句点发送即转双语
            _bilingualOutgoing = YES;
            _autoSkipSameLanguage = YES;
            _targetLanguage = @"zh-CN";
            _outgoingTargetLanguage = @"en";
            _translationEngine = WATranslationEngineGoogleFree;
            _googleCloudApiKey = @"";
            _liquidGlassEnabled = NO;
            [self save];
        } else {
            _autoTranslateIncoming = [defaults boolForKey:kAutoTranslateIncoming];
            _autoTranslateOutgoing = [defaults objectForKey:kAutoTranslateOutgoing] ? [defaults boolForKey:kAutoTranslateOutgoing] : YES;
            _bilingualOutgoing = [defaults objectForKey:kBilingualOutgoing] ? [defaults boolForKey:kBilingualOutgoing] : YES;
            _autoSkipSameLanguage = [defaults objectForKey:kAutoSkipSameLanguage] ? [defaults boolForKey:kAutoSkipSameLanguage] : YES;
            _targetLanguage = [defaults stringForKey:kTargetLanguage] ?: @"zh-CN";
            _outgoingTargetLanguage = [defaults stringForKey:kOutgoingTargetLanguage] ?: @"en";
            _translationEngine = (WATranslationEngine)[defaults integerForKey:kTranslationEngine];
            _googleCloudApiKey = [defaults stringForKey:kGoogleCloudApiKey] ?: @"";
            _liquidGlassEnabled = [defaults boolForKey:kLiquidGlassEnabled];
        }
        // transient，不从磁盘读
        _currentChatJID = nil;
        _currentChatName = nil;
    }
    return self;
}

- (void)save {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:_autoTranslateIncoming forKey:kAutoTranslateIncoming];
    [defaults setBool:_autoTranslateOutgoing forKey:kAutoTranslateOutgoing];
    [defaults setBool:_bilingualOutgoing forKey:kBilingualOutgoing];
    [defaults setBool:_autoSkipSameLanguage forKey:kAutoSkipSameLanguage];
    [defaults setObject:_targetLanguage forKey:kTargetLanguage];
    [defaults setObject:_outgoingTargetLanguage forKey:kOutgoingTargetLanguage];
    [defaults setInteger:_translationEngine forKey:kTranslationEngine];
    [defaults setObject:_googleCloudApiKey forKey:kGoogleCloudApiKey];
    [defaults setBool:_liquidGlassEnabled forKey:kLiquidGlassEnabled];
    // 注意：per-chat 表由 setAutoTranslate:/removeAutoTranslateForChatJID: 直接写入，此处不重复写
    [defaults synchronize];
}

+ (NSDictionary<NSString *, NSString *> *)supportedLanguages {
    return @{
        @"zh-CN": @"中文 (简体)",
        @"zh-TW": @"中文 (繁體)",
        @"en": @"English (英语)",
        @"es": @"Español (西班牙语)",
        @"ja": @"日本語 (日语)",
        @"ko": @"한국어 (韩语)",
        @"ru": @"Русский (俄语)",
        @"fr": @"Français (法语)",
        @"de": @"Deutsch (德语)",
        @"ar": @"العربية (阿拉伯语)",
        @"pt": @"Português (葡萄牙语)",
        @"it": @"Italiano (意大利语)"
    };
}

#pragma mark - Per-Chat Auto-Translate

- (NSMutableDictionary *)mutablePerChatMap {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *saved = [defaults dictionaryForKey:kPerChatTranslate];
    return saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

- (BOOL)shouldAutoTranslateChatJID:(NSString *)jid {
    // 总开关语义：开 = 所有聊天都自动翻译；按聊天的单独设置作为覆盖（可单独关闭）
    if (!self.autoTranslateIncoming) return NO;
    if (jid.length == 0) return YES;
    BOOL explicit = NO;
    if ([self hasExplicitSettingForChatJID:jid enabled:&explicit]) {
        return explicit;
    }
    return YES;
}

- (BOOL)hasExplicitSettingForChatJID:(NSString *)jid enabled:(BOOL *)outEnabled {
    if (jid.length == 0) return NO;
    NSDictionary *entry = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPerChatTranslate][jid];
    if (![entry isKindOfClass:[NSDictionary class]]) return NO;
    if (outEnabled) *outEnabled = [entry[@"enabled"] boolValue];
    return YES;
}

- (void)setAutoTranslate:(BOOL)enabled forChatJID:(NSString *)jid chatName:(NSString *)name {
    if (jid.length == 0) return;
    NSMutableDictionary *map = [self mutablePerChatMap];
    map[jid] = @{
        @"name": name.length > 0 ? name : jid,
        @"enabled": @(enabled),
        @"updatedAt": @([[NSDate date] timeIntervalSince1970])
    };
    // 淘汰最旧的，防止无限增长
    if (map.count > kMaxPerChatEntries) {
        NSArray *sorted = [map keysSortedByValueWithOptions:0 usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"updatedAt"] compare:b[@"updatedAt"]]; // 升序：最旧在前
        }];
        for (NSUInteger i = 0; i < map.count - kMaxPerChatEntries; i++) {
            [map removeObjectForKey:sorted[i]];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:[map copy] forKey:kPerChatTranslate];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)removeAutoTranslateForChatJID:(NSString *)jid {
    if (jid.length == 0) return;
    NSMutableDictionary *map = [self mutablePerChatMap];
    [map removeObjectForKey:jid];
    [[NSUserDefaults standardUserDefaults] setObject:[map copy] forKey:kPerChatTranslate];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSArray<NSString *> *)allPerChatJIDsSorted {
    NSDictionary *map = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPerChatTranslate];
    if (![map isKindOfClass:[NSDictionary class]] || map.count == 0) return @[];
    // 过滤脏数据：只保留字典型条目
    NSMutableDictionary *valid = [NSMutableDictionary dictionary];
    for (NSString *key in map) {
        id value = map[key];
        if ([value isKindOfClass:[NSDictionary class]]) valid[key] = value;
    }
    if (valid.count == 0) return @[];
    return [valid keysSortedByValueWithOptions:0 usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        // 降序：最近设置的在前；顺带把开启的排前面
        BOOL aOn = [a[@"enabled"] boolValue];
        BOOL bOn = [b[@"enabled"] boolValue];
        if (aOn != bOn) return aOn ? NSOrderedAscending : NSOrderedDescending;
        return [b[@"updatedAt"] compare:a[@"updatedAt"]];
    }];
}

- (NSDictionary *)perChatEntryForJID:(NSString *)jid {
    if (jid.length == 0) return nil;
    NSDictionary *entry = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPerChatTranslate][jid];
    return [entry isKindOfClass:[NSDictionary class]] ? entry : nil;
}

@end
