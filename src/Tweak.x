#import "Common.h"
#import "Settings/WATweakSettings.h"
#import "Settings/WATweakSettingsViewController.h"
#import "Translation/WATranslationManager.h"
#import "Translation/WAFloatingTranslateButton.h"
#import "Translation/WAChatInfoResolver.h"
#import "IconPicker/WAIconPickerViewController.h"
#import <objc/message.h>

// 启动自诊断报告（设置页可查看）
static NSString *waTweakDiagReport = nil;

// -richTextFromMessage hook 调用计数（真正的文本入口候选）
// -setText: hook 调用计数（数据源写入入口）

// Label 扫描器计数（诊断）
// 分阶段过滤计数（定位卡在哪）
// 正在翻译中的文本（去重，避免重复请求）
static NSMutableSet *waTweakTranslatingTexts = nil;

// 递归查找指定类的视图（用于检测上下文菜单是否显示）
// 放在文件顶部：WAChatViewController 的 hook 在 WAChatBar 之前使用它
static BOOL waTweakFindViewOfClassDepth(UIView *view, Class cls, int depth);
static BOOL waTweakFindViewOfClass(UIView *view, Class cls) {
    return waTweakFindViewOfClassDepth(view, cls, 0);
}
static BOOL waTweakFindViewOfClassDepth(UIView *view, Class cls, int depth) {
    if (!view || !cls || depth > 15) return NO;
    if ([view isKindOfClass:cls]) return YES;
    for (UIView *sub in view.subviews) {
        if (waTweakFindViewOfClassDepth(sub, cls, depth + 1)) return YES;
    }
    return NO;
}

#pragma mark - Hook: File Deletion Protection (Preserve Revoked Media & View-Once)


#pragma mark - Hook: Anti-Revoke (WAChatStorage & WAMessage)


#pragma mark - Hook: WAMessage (Anti-Revoke, View-Once & Incoming Translation)


#pragma mark - Hook: Chat View Controller (Floating Translate Ball & ScrollView Reload)

%hook WAChatViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(waTweak_reloadMessagesSafely) name:@"WATweakReloadMessagesNotification" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    // 尽早记录当前聊天标识（JID 优先，名称兜底），避免首屏渲染时取不到
    [self waTweak_updateCurrentChatIdentity];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    // 再确认一次（有些版本 viewWillAppear 时会话对象还没就绪）
    [self waTweak_updateCurrentChatIdentity];


}

%new
- (BOOL)waTweak_isUserInteracting {
    // 检查聊天内的 scroll view 是否正在被触摸/拖动（长按也算 tracking）
    __block BOOL interacting = NO;
    @try {
        [self waTweak_enumerateScrollViews:self.view depth:0 block:^(UIScrollView *sv) {
            if (sv.isTracking || sv.isDragging || sv.isDecelerating) {
                interacting = YES;
            }
        }];
    } @catch (NSException *e) {}
    return interacting;
}

%new
- (void)waTweak_enumerateScrollViews:(UIView *)view depth:(int)depth block:(void (^)(UIScrollView *))block {
    if (!view || depth > 12 || !block) return;
    if ([view isKindOfClass:[UIScrollView class]]) {
        block((UIScrollView *)view);
    }
    for (UIView *sub in view.subviews) {
        [self waTweak_enumerateScrollViews:sub depth:depth + 1 block:block];
    }
}

%new
%new
%new
%new
%new
%new
- (void)waTweak_processMessageTextView:(UIView *)view midX:(CGFloat)midX chatView:(UIView *)chatView {

    NSString *text = nil;
    CGFloat fontSize = 0;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)view;
        text = l.text;
        fontSize = l.font.pointSize;
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        text = tv.text;
        fontSize = tv.font.pointSize;
    } else {
        return;
    }

    CGRect frameInChat = [view convertRect:view.bounds toView:chatView];
    CGFloat chatH = CGRectGetHeight(chatView.bounds);

    // 位置：左边缘偏左才是对方消息（长消息气泡占满宽度时中心点也在中间，不能用中心点判断）
    // 对方气泡左对齐（minX 很小），自己的气泡右对齐（minX 很大）

    [self waTweak_translateTextView:view originalText:text];
}

%new
- (void)waTweak_translateTextView:(UIView *)view originalText:(NSString *)text {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    WATranslationManager *manager = [WATranslationManager sharedManager];

    NSString *targetLang = settings.targetLanguage ?: @"zh-CN";
    targetLang = [manager effectiveIncomingTargetForText:text configuredTarget:targetLang];

    NSString *cached = [manager cachedTranslationForText:text targetLanguage:targetLang];
    if (cached.length > 0) {
        NSString *bilingual = [manager formatIncomingMessageWithOriginal:text translation:cached];
        if (bilingual.length > 0 && ![bilingual isEqualToString:text]) {
            if ([view isKindOfClass:[UILabel class]]) {
                ((UILabel *)view).text = bilingual;
                [(UILabel *)view sizeToFit];
            } else if ([view isKindOfClass:[UITextView class]]) {
                ((UITextView *)view).text = bilingual;
            }
            [view.superview setNeedsLayout];
                }
        return;
    }

    // 去重：同一文本翻译中则跳过（P1-2，避免重复请求）
    @synchronized(self) {
        if (!waTweakTranslatingTexts) waTweakTranslatingTexts = [NSMutableSet set];
        if ([waTweakTranslatingTexts containsObject:text]) return;
        [waTweakTranslatingTexts addObject:text];
    }
    __weak UIView *weakView = view;
    NSString *origCopy = [text copy];
    [manager translateText:text targetLanguage:targetLang completion:^(NSString *translated, NSError *error) {
        if (translated.length > 0 && ![translated isEqualToString:origCopy]) {
            NSString *bilingual = [manager formatIncomingMessageWithOriginal:origCopy translation:translated];
            @synchronized(self) {
                [waTweakTranslatingTexts removeObject:origCopy];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                UIView *strongView = weakView;
                if (!strongView || bilingual.length == 0) return;
                NSString *current = nil;
                if ([strongView isKindOfClass:[UILabel class]]) current = ((UILabel *)strongView).text;
                else if ([strongView isKindOfClass:[UITextView class]]) current = ((UITextView *)strongView).text;
                else return;
                if ([current isEqualToString:origCopy]) {
                    if ([strongView isKindOfClass:[UILabel class]]) {
                        ((UILabel *)strongView).text = bilingual;
                        [(UILabel *)strongView sizeToFit];
                    } else if ([strongView isKindOfClass:[UITextView class]]) {
                        ((UITextView *)strongView).text = bilingual;
                    }
                    [strongView.superview setNeedsLayout];
                                }
            });
        } else {
            @synchronized(self) {
                [waTweakTranslatingTexts removeObject:origCopy];
            }
            if (error) {
                WALog(@"[Translation] label: failed: %@", error.localizedDescription);
            }
        }
    }];
}

%new
- (void)waTweak_updateCurrentChatIdentity {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    NSString *identifier = [WAChatInfoResolver chatIdentifierForViewController:self];
    if (identifier.length > 0) {
        settings.currentChatJID = identifier;
        settings.currentChatName = [WAChatInfoResolver chatNameForViewController:self];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    // 离开聊天即清除，避免后台渲染时误用
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    settings.currentChatJID = nil;
    settings.currentChatName = nil;
    %orig;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"WATweakReloadMessagesNotification" object:nil];
    %orig;
}

%new
- (void)waTweak_reloadMessagesSafely {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 原生菜单（长按选项/弹窗）显示时跳过刷新，避免把菜单顶掉；2 秒后重试，最多 3 次
        if ([self waTweak_isMenuShowing]) {
            NSNumber *retries = objc_getAssociatedObject(self, "waTweak_reloadRetries");
            NSInteger n = retries.integerValue;
            if (n < 3) {
                objc_setAssociatedObject(self, "waTweak_reloadRetries", @(n + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self waTweak_reloadMessagesSafely];
                });
            } else {
                objc_setAssociatedObject(self, "waTweak_reloadRetries", @(0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            return;
        }
        objc_setAssociatedObject(self, "waTweak_reloadRetries", @(0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL skipped = [self waTweak_reloadAllScrollViews:self.view];
        if (skipped) {
            // 滚动中跳过了翻译刷新，1.5 秒后重试一次，保证译文能实时显示
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self waTweak_reloadAllScrollViews:self.view];
            });
        }
    });
}

%new
- (BOOL)waTweak_isMenuShowing {
    if (self.presentedViewController) return YES;
    if ([UIMenuController sharedMenuController].isMenuVisible) return YES;
    // iOS 13+ 长按上下文菜单（私有类，只做存在性检查，不链接）
    Class ctxMenuClass = NSClassFromString(@"_UIContextMenuContainerView");
    if (ctxMenuClass) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (waTweakFindViewOfClass(w, ctxMenuClass)) return YES;
        }
    }
    return NO;
}

%new
- (BOOL)waTweak_reloadAllScrollViews:(UIView *)view {
    return [self waTweak_reloadAllScrollViews:view depth:0];
}
- (BOOL)waTweak_reloadAllScrollViews:(UIView *)view depth:(int)depth {
    if (!view || depth > 15) return NO;
    BOOL skipped = NO;
    if ([view isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)view;
        if (!tv.isDragging && !tv.isDecelerating) {
            [tv reloadData];
        } else {
            skipped = YES;
        }
    } else if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)view;
        if (!cv.isDragging && !cv.isDecelerating) {
            [cv reloadData];
        } else {
            skipped = YES;
        }
    }
    for (UIView *sub in view.subviews) {
        if ([self waTweak_reloadAllScrollViews:sub depth:depth + 1]) skipped = YES;
    }
    return skipped;
}

%new
%end

#pragma mark - Hook: Chat Bar (Inline Translate Button)

// 递归查找输入框：优先第一响应者（正在输入的），否则取第一个有文字的，再否则第一个
// 放在文件顶部：多个 hook 块都要用
static UITextView *waTweakFindTextViewInView(UIView *view, UITextView **fallback) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        if (tv.isFirstResponder) return tv;
        if (fallback && !*fallback) *fallback = tv;
    }
    for (UIView *sub in view.subviews) {
        UITextView *found = waTweakFindTextViewInView(sub, fallback);
        if (found) return found;
    }
    return nil;
}

%hook WAChatBar

// 注意：不再 hook didMoveToWindow（Logos 误报 new method），
// 输入监听改由全局单例 WAEagerTranslationObserver 在 %ctor 中注册

%new
- (void)waTweak_doEagerTranslation {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    if (!settings.autoTranslateOutgoing) return;
    UITextView *tv = [self waTweak_findInputTextView];
    NSString *text = [tv.text copy];
    if (text.length == 0) {
        // 输入框空了，清理翻译记录
        objc_setAssociatedObject(self, "waTweak_eagerOriginal", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "waTweak_eagerBilingual", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    // 确定要翻译的源文本
    NSString *sourceToTranslate = nil;
    if ([text containsString:@"──────────────"]) {
        // 已经是双语：判断用户是追加还是改了内容
        NSString *prevBilingual = objc_getAssociatedObject(self, "waTweak_eagerBilingual");
        NSString *prevOriginal = objc_getAssociatedObject(self, "waTweak_eagerOriginal");
        if (prevBilingual.length > 0 && prevOriginal.length > 0 && [text hasPrefix:prevBilingual]) {
            // 纯追加：新源 = 原原文 + 追加部分
            NSString *appended = [[text substringFromIndex:prevBilingual.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (appended.length == 0) return;
            sourceToTranslate = [prevOriginal stringByAppendingString:appended];
            WALog(@"[Translation] Outgoing eager: user appended text, re-translating");
        } else {
            // 改了其他部分：取分隔符后的内容作为新源
            NSRange r = [text rangeOfString:@"──────────────"];
            NSString *after = [[text substringFromIndex:r.location + r.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (after.length == 0 || [after isEqualToString:prevOriginal]) return; // 只改了译文或无实质变化
            sourceToTranslate = after;
            WALog(@"[Translation] Outgoing eager: user edited, re-translating");
        }
    } else {
        sourceToTranslate = text;
    }

    WATranslationManager *manager = [WATranslationManager sharedManager];
    NSString *targetLang = settings.outgoingTargetLanguage ?: @"en";
    if (settings.autoSkipSameLanguage && [manager isText:sourceToTranslate alreadyInLanguage:targetLang]) return;
    NSString *cached = [manager cachedTranslationForText:sourceToTranslate targetLanguage:targetLang];
    if (cached.length > 0) {
        [self waTweak_applyEagerTranslation:cached originalText:sourceToTranslate expectedCurrent:text];
        return;
    }
    WALog(@"[Translation] Outgoing eager: translating");
    NSString *requestSource = [sourceToTranslate copy];
    NSString *requestText = [text copy];
    [manager translateText:sourceToTranslate targetLanguage:targetLang completion:^(NSString *translatedText, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UITextView *currentTV = [self waTweak_findInputTextView];
            if (!currentTV) return;
            // 输入框内容与请求时不一致（继续输入/已发送）就不覆盖，下次停顿再处理
            if (![currentTV.text isEqualToString:requestText]) return;
            if (translatedText.length > 0) {
                [self waTweak_applyEagerTranslation:translatedText originalText:requestSource expectedCurrent:requestText];
            } else {
                WALog(@"[Translation] Outgoing eager failed: %@", error.localizedDescription);
                [[WAFloatingTranslateButton sharedButton] showBriefToast:@"⚠️ 自动翻译失败，请检查网络" inView:currentTV.superview];
            }
        });
    }];
}

%new
- (void)waTweak_applyEagerTranslation:(NSString *)translated originalText:(NSString *)original expectedCurrent:(NSString *)expected {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    UITextView *tv = [self waTweak_findInputTextView];
    if (!tv || ![tv.text isEqualToString:expected]) return;
    NSString *finalText = settings.bilingualOutgoing
        ? [[WATranslationManager sharedManager] formatBilingualTextWithTranslation:translated originalText:original]
        : translated;
    tv.text = finalText;
    if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) [tv.delegate textViewDidChange:tv];
    // 记录原文与双语结果，供后续追加/编辑时重新翻译
    objc_setAssociatedObject(self, "waTweak_eagerOriginal", original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "waTweak_eagerBilingual", finalText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WALog(@"[Translation] Outgoing eager: applied bilingual to input");
}

%new
%new
- (UITextView *)waTweak_findInputTextView {
    // 优先直接属性，取不到再递归找（优先第一响应者）
    UITextView *tv = nil;
    @try { tv = self.inputTextView; } @catch (NSException *e) {}
    if ([tv isKindOfClass:[UITextView class]]) return tv;
    UITextView *fallback = nil;
    UITextView *found = waTweakFindTextViewInView(self, &fallback);
    return found ?: fallback;
}

// 发送时自动翻译（主拦截点）：点发送按钮 → 翻译输入框文字 → 写回双语 → 再走正常发送
// 直接写输入框是最稳的：无论 WhatsApp 内部读参数还是读输入框，都能生效
- (void)sendButtonTapped:(id)sender {
    // 重入保护：这是翻译完成后的重发，直接走原始发送
    NSNumber *bypass = objc_getAssociatedObject(self, "waTweak_sendBypass");
    if (bypass.boolValue) {
        objc_setAssociatedObject(self, "waTweak_sendBypass", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(sender);
        return;
    }

    // 翻译中的重复点击直接吞掉，避免重复发出
    NSNumber *inFlight = objc_getAssociatedObject(self, "waTweak_translateInFlight");
    if (inFlight.boolValue) {
        WALog(@"[Translation] Outgoing: translate in flight, ignoring duplicate tap");
        return;
    }

    WATweakSettings *settings = [WATweakSettings sharedSettings];
    if (settings.autoTranslateOutgoing) {
        UITextView *tv = [self waTweak_findInputTextView];
        NSString *inputText = tv.text;
        if (inputText.length > 0 && ![inputText containsString:@"──────────────"]) {
            WATranslationManager *manager = [WATranslationManager sharedManager];
            NSString *targetLang = settings.outgoingTargetLanguage ?: @"en";
            WALog(@"[Translation] Outgoing: sendButtonTapped intercept -> %@", targetLang);

            BOOL needsTranslation = !(settings.autoSkipSameLanguage && [manager isText:inputText alreadyInLanguage:targetLang]);
            if (needsTranslation) {
                NSString *cached = [manager cachedTranslationForText:inputText targetLanguage:targetLang];
                if (cached.length > 0) {
                    NSString *finalText = settings.bilingualOutgoing ? [manager formatBilingualTextWithTranslation:cached originalText:inputText] : cached;
                    tv.text = finalText;
                    if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) [tv.delegate textViewDidChange:tv];
                    objc_setAssociatedObject(self, "waTweak_sendBypass", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [self sendButtonTapped:sender];
                    return;
                }
                // 异步翻译后写回输入框再发送；失败则原文发出
                __weak typeof(self) weakSelf = self;
                __weak UITextView *weakTV = tv;
                objc_setAssociatedObject(self, "waTweak_translateInFlight", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                // 超时保护：8秒未完成则按原文发送，防止按钮永久锁死（P1-3）
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelfTimeout = weakSelf;
                    if (!strongSelfTimeout) return;
                    NSNumber *stillInFlight = objc_getAssociatedObject(strongSelfTimeout, "waTweak_translateInFlight");
                    if (stillInFlight.boolValue) {
                        WALog(@"[Translation] Outgoing: timeout, sending original");
                        objc_setAssociatedObject(strongSelfTimeout, "waTweak_translateInFlight", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        objc_setAssociatedObject(strongSelfTimeout, "waTweak_sendBypass", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        [strongSelfTimeout sendButtonTapped:sender];
                    }
                });
                [manager translateText:inputText targetLanguage:targetLang completion:^(NSString *translatedText, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) return;
                        // 超时已处理则不再重复发送
                        NSNumber *inFlightCheck = objc_getAssociatedObject(strongSelf, "waTweak_translateInFlight");
                        if (!inFlightCheck.boolValue) return;
                        objc_setAssociatedObject(strongSelf, "waTweak_translateInFlight", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        UITextView *strongTV = weakTV;
                        NSString *toSend = inputText;
                        if (translatedText.length > 0) {
                            toSend = settings.bilingualOutgoing ? [manager formatBilingualTextWithTranslation:translatedText originalText:inputText] : translatedText;
                        } else {
                            WALog(@"[Translation] Outgoing: failed: %@", error.localizedDescription);
                        }
                        // 用户在翻译期间又改了输入框，就不覆盖，直接发当前内容
                        if (strongTV && [strongTV.text isEqualToString:inputText]) {
                            strongTV.text = toSend;
                            if ([strongTV.delegate respondsToSelector:@selector(textViewDidChange:)]) [strongTV.delegate textViewDidChange:strongTV];
                        }
                        objc_setAssociatedObject(strongSelf, "waTweak_sendBypass", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        [strongSelf sendButtonTapped:sender];
                    });
                }];
                return;
            }
        }
    }
    %orig(sender);
}

// 发送时自动翻译：输入原文点发送 → 自动转为双语发出，无需手动点悬浮球
- (void)sendTextMessage:(NSString *)text {
    WATweakSettings *settings = [WATweakSettings sharedSettings];

    // 重入保护：这是翻译完成后的重发，直接走原始发送
    NSNumber *bypass = objc_getAssociatedObject(self, "waTweak_sendBypass");
    if (bypass.boolValue) {
        objc_setAssociatedObject(self, "waTweak_sendBypass", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(text);
        return;
    }

    if (settings.autoTranslateOutgoing && text.length > 0) {
        WATranslationManager *manager = [WATranslationManager sharedManager];
        NSString *targetLang = settings.outgoingTargetLanguage ?: @"en";

        // 已经是双语格式（悬浮球手动翻译过）→ 直接发送，不重复翻译
        if ([text containsString:@"──────────────"]) {
            %orig(text);
            return;
        }
        // 已经是目标语言 → 直接发送
        if (settings.autoSkipSameLanguage && [manager isText:text alreadyInLanguage:targetLang]) {
            %orig(text);
            return;
        }
        // 缓存命中 → 直接发送翻译结果
        NSString *cached = [manager cachedTranslationForText:text targetLanguage:targetLang];
        if (cached.length > 0) {
            NSString *finalText = settings.bilingualOutgoing ? [manager formatBilingualTextWithTranslation:cached originalText:text] : cached;
            objc_setAssociatedObject(self, "waTweak_sendBypass", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            %orig(finalText);
            return;
        }
        // 异步翻译后发送；失败则原文发出，不阻塞发送
        __weak typeof(self) weakSelf = self;
        [manager translateText:text targetLanguage:targetLang completion:^(NSString *translatedText, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                NSString *toSend = text;
                if (translatedText.length > 0) {
                    toSend = settings.bilingualOutgoing ? [manager formatBilingualTextWithTranslation:translatedText originalText:text] : translatedText;
                }
                objc_setAssociatedObject(strongSelf, "waTweak_sendBypass", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [strongSelf sendTextMessage:toSend];
            });
        }];
        return;
    }
    %orig;
}

%end

#pragma mark - Hook: Settings UI Entry (WASettingsViewController)

%hook WASettingsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    UIBarButtonItem *plusBtn = [[UIBarButtonItem alloc] initWithTitle:@"WhatsApp+" style:UIBarButtonItemStylePlain target:self action:@selector(waTweak_openSettings)];
    UIBarButtonItem *iconBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"app.badge"] style:UIBarButtonItemStylePlain target:self action:@selector(waTweak_openIconPicker)];
    
    self.navigationItem.rightBarButtonItems = @[plusBtn, iconBtn];
}

%new
- (void)waTweak_openSettings {
    WATweakSettingsViewController *settingsVC = [[WATweakSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

%new
- (void)waTweak_openIconPicker {
    WAIconPickerViewController *pickerVC = [[WAIconPickerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pickerVC];
    pickerVC.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:pickerVC action:@selector(dismissPicker)];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

%end

#pragma mark - Group: LiquidGlass (Meta Lab Features from WAIconPicker)

%group LiquidGlass

%hook WDSLiquidGlass
+ (BOOL)hasLiquidGlassLaunched { return YES; }
+ (BOOL)isM0Enabled { return YES; }
+ (BOOL)isM1Enabled { return YES; }
+ (BOOL)isM1_5Enabled { return YES; }
+ (BOOL)isM1_5ContextMenuEnabled { return YES; }
+ (BOOL)isLargerComposerEnabled { return YES; }
+ (BOOL)isNewLiquidGlassLayoutEnabled { return YES; }
%end

%hook WAABProperties
- (BOOL)ios_liquid_glass_enabled { return YES; }
- (BOOL)ios_liquid_glass_launched { return YES; }
- (BOOL)ios_liquid_glass_m1 { return YES; }
- (BOOL)ios_liquid_glass_m_1_5 { return YES; }
- (BOOL)ios_liquid_glass_m_1_5_context_menu { return YES; }
- (BOOL)ios_liquid_glass_media_m0 { return YES; }
- (BOOL)ios_liquid_glass_larger_composer { return YES; }
- (BOOL)ios_liquid_glass_media_editor_enabled { return YES; }
- (BOOL)ios_liquid_glass_calling_improvement_enabled { return YES; }
- (BOOL)ios_liquid_glass_workaround_attachment_tray { return YES; }
- (BOOL)status_viewer_redesign_enabled { return YES; }
%end

%hook WALiquidGlassOverrideMethodUserDefaults
- (BOOL)isEnabled { return YES; }
%end

%hook IGLiquidGlassExperimentHelper
- (BOOL)isEnabled { return YES; }
%end

%hook WAGenericMediaBrowserViewController
- (BOOL)isLiquidGlassLayoutInMediaBrowserEnabled { return YES; }
%end

%hook WAGenericMediaBrowserViewControllerV2
- (BOOL)isLiquidGlassLayoutInMediaBrowserEnabled { return YES; }
%end

%hook WAMediaBrowserVideoCell
+ (void)setNewLiquidGlassLayoutEnabled:(BOOL)arg0 {
    arg0 = YES;
    %orig;
}
%end

%end

#pragma mark - Constructor

static NSString *waTweakRunDiagnostics(void);

static NSString *waTweakRunDiagnostics(void) {
    NSMutableString *r = [NSMutableString string];
    // WAMessage
    Class msgClass = objc_getClass("WAMessage");
    [r appendFormat:@"WAMessage 类: %@\n", msgClass ? @"存在" : @"缺失"];
    if (msgClass) {
        [r appendFormat:@"  -text: %@\n", [msgClass instancesRespondToSelector:@selector(text)] ? @"有" : @"无"];
        [r appendFormat:@"  -messageText: %@\n", [msgClass instancesRespondToSelector:@selector(messageText)] ? @"有" : @"无"];
        [r appendFormat:@"  -isFromMe: %@\n", [msgClass instancesRespondToSelector:@selector(isFromMe)] ? @"有" : @"无"];
        // 列出含 text 的方法（找真正的渲染入口）
        [r appendString:@"  含 text 的方法:\n"];
        unsigned int mcount = 0;
        Method *methods = class_copyMethodList(msgClass, &mcount);
        int shown = 0;
        for (unsigned int i = 0; i < mcount && shown < 12; i++) {
            const char *mname = sel_getName(method_getName(methods[i]));
            if (mname) {
                NSString *ms = [NSString stringWithUTF8String:mname].lowercaseString;
                if ([ms containsString:@"text"]) {
                    [r appendFormat:@"    -%s\n", mname];
                    shown++;
                }
            }
        }
        free(methods);
        if (shown == 0) [r appendString:@"    （无）\n"];
        // 找消息方向相关方法（isFromMe 的替代）
        [r appendString:@"  方向相关的方法:\n"];
        methods = class_copyMethodList(msgClass, &mcount);
        shown = 0;
        for (unsigned int i = 0; i < mcount && shown < 10; i++) {
            const char *mname = sel_getName(method_getName(methods[i]));
            if (mname) {
                NSString *ms = [NSString stringWithUTF8String:mname].lowercaseString;
                if ([ms containsString:@"fromme"] || [ms containsString:@"isfrom"] ||
                    [ms containsString:@"outgoing"] || [ms containsString:@"sender"] ||
                    ([ms containsString:@"from"] && [ms containsString:@"me"])) {
                    [r appendFormat:@"    -%s\n", mname];
                    shown++;
                }
            }
        }
        free(methods);
        if (shown == 0) [r appendString:@"    （无）\n"];
    } else {
        // 找候选：类名含 Message 的 WA 相关类（最多列 10 个）
        int numClasses = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
        numClasses = objc_getClassList(classes, numClasses);
        int shown = 0;
        for (int i = 0; i < numClasses && shown < 10; i++) {
            const char *name = class_getName(classes[i]);
            if (name && strstr(name, "Message") && (strstr(name, "WA") == name || strstr(name, "WhatsApp"))) {
                [r appendFormat:@"  候选: %s\n", name];
                shown++;
            }
        }
        free(classes);
        if (shown == 0) [r appendString:@"  （无候选类）\n"];
    }
    // WAChatBar
    Class barClass = objc_getClass("WAChatBar");
    [r appendFormat:@"WAChatBar 类: %@\n", barClass ? @"存在" : @"缺失"];
    if (barClass) {
        [r appendFormat:@"  -sendButtonTapped:: %@\n", [barClass instancesRespondToSelector:@selector(sendButtonTapped:)] ? @"有" : @"无"];
        [r appendFormat:@"  -sendTextMessage:: %@\n", [barClass instancesRespondToSelector:@selector(sendTextMessage:)] ? @"有" : @"无"];
    }
    // WAChatViewController
    Class vcClass = objc_getClass("WAChatViewController");
    [r appendFormat:@"WAChatViewController 类: %@\n", vcClass ? @"存在" : @"缺失"];
    // WAMessageContainerView 结构（FLEX 确认的消息容器，找文本入口）
    Class containerClass = objc_getClass("WAMessageContainerView");
    [r appendFormat:@"WAMessageContainerView 类: %@\n", containerClass ? @"存在" : @"缺失"];
    if (containerClass) {
        [r appendString:@"  属性:\n"];
        unsigned int pcount = 0;
        objc_property_t *props = class_copyPropertyList(containerClass, &pcount);
        int pshown = 0;
        for (unsigned int i = 0; i < pcount && pshown < 12; i++) {
            const char *pname = property_getName(props[i]);
            if (pname) { [r appendFormat:@"    %s\n", pname]; pshown++; }
        }
        free(props);
        if (pshown == 0) [r appendString:@"    （无属性）\n"];
        [r appendString:@"  实例变量:\n"];
        unsigned int icount = 0;
        Ivar *ivars = class_copyIvarList(containerClass, &icount);
        int ishown = 0;
        for (unsigned int i = 0; i < icount && ishown < 12; i++) {
            const char *iname = ivar_getName(ivars[i]);
            if (iname) { [r appendFormat:@"    %s\n", iname]; ishown++; }
        }
        free(ivars);
        if (ishown == 0) [r appendString:@"    （无）\n"];
    }
    return [r copy];
}


// 供设置页诊断入口调用
NSString *waTweakDiagnosticReport(void) {
    return waTweakDiagReport ?: @"诊断尚未运行";
}

// 全局输入监听：替代 WAChatBar 的 didMoveToWindow hook（避开 Logos 误报）
static void waTweak_globalInputDidChange(NSNotification *note) {
    UITextView *tv = note.object;
    if (![tv isKindOfClass:[UITextView class]]) return;
    // 找到所属的 WAChatBar
    UIView *v = tv;
    id chatBar = nil;
    while (v) {
        if ([NSStringFromClass([v class]) isEqualToString:@"WAChatBar"]) {
            chatBar = v;
            break;
        }
        v = v.superview;
    }
    if (!chatBar) return;
    // 触发该 bar 的 eager 翻译（防抖 1.5s）
    [NSObject cancelPreviousPerformRequestsWithTarget:chatBar selector:@selector(waTweak_doEagerTranslation) object:nil];
    [chatBar performSelector:@selector(waTweak_doEagerTranslation) withObject:nil afterDelay:1.5];
}

%ctor {
    @autoreleasepool {
        %init;
        // 注册全局输入监听
        [[NSNotificationCenter defaultCenter] addObserverForName:UITextViewTextDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            waTweak_globalInputDidChange(note);
        }];
        waTweakDiagReport = waTweakRunDiagnostics();
        WALog(@"[Diag]\n%@", waTweakDiagReport);
        if ([WATweakSettings sharedSettings].liquidGlassEnabled) {
            [WAIconPickerViewController applyLiquidGlassDefaultsIfNeeded];
            if (objc_getClass("WDSLiquidGlass") != nil || objc_getClass("WAABProperties") != nil) {
                %init(LiquidGlass);
            }
        }
        WALog(@"WhatsApp+ loaded successfully with WAFloatingTranslateButton & Multi-Engine Translation.");
    }
}
