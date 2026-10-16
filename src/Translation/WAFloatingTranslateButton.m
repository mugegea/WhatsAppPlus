#import "WAFloatingTranslateButton.h"
#import <objc/runtime.h>
#import "WATranslationManager.h"
#import "WAChatInfoResolver.h"
#import "../Settings/WATweakSettings.h"
#import "../Settings/WATweakSettingsViewController.h"
#import "../Common.h"

static NSString *const kFloatingButtonYPosKey = @"WATweak_FloatingButtonYPos";

@interface WAFloatingTranslateButton ()
@property (nonatomic, weak) UIViewController *currentVC;
@property (nonatomic, assign) CGPoint lastPanPoint;
@property (nonatomic, strong) UILabel *titleLbl;
- (void)waTweakInspectMessageContainer;

@end


@implementation WAFloatingTranslateButton

+ (instancetype)sharedButton {
    static WAFloatingTranslateButton *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAFloatingTranslateButton alloc] initWithFrame:CGRectMake(0, 0, 72, 34)];
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 17.0;
        self.layer.masksToBounds = NO;
        self.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.92];
        
        // Border & shadow
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 5.0;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        
        _titleLbl = [[UILabel alloc] initWithFrame:self.bounds];
        _titleLbl.textAlignment = NSTextAlignmentCenter;
        _titleLbl.textColor = [UIColor whiteColor];
        _titleLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        _titleLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_titleLbl];
        
        [self updateAppearance];
        
        // Tap gesture
        [self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
        
        // Pan gesture for dragging
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        
        // Long press gesture
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.45;
        [self addGestureRecognizer:longPress];
    }
    return self;
}

- (void)updateAppearance {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    BOOL isBilingual = settings.bilingualOutgoing;
    NSString *base = isBilingual ? @"🌐 双语" : @"🌐 译";
    // 当前聊天开了自动翻译就加个 ✓ 角标，一眼可见
    if ([settings shouldAutoTranslateChatJID:settings.currentChatJID]) {
        base = [base stringByAppendingString:@"✓"];
    }
    self.titleLbl.text = base;
}

- (void)attachToViewController:(UIViewController *)vc {
    if (!vc || !vc.view) return;
    self.currentVC = vc;
    
    [self updateAppearance];
    
    // Calculate initial or saved position
    CGFloat screenW = vc.view.bounds.size.width;
    CGFloat screenH = vc.view.bounds.size.height;
    CGFloat btnW = 72.0;
    CGFloat btnH = 34.0;
    
    CGFloat savedY = [[NSUserDefaults standardUserDefaults] floatForKey:kFloatingButtonYPosKey];
    if (savedY < 100.0 || savedY > screenH - 120.0) {
        savedY = screenH - 160.0;
    }
    
    CGFloat initialX = screenW - btnW - 10.0;
    self.frame = CGRectMake(initialX, savedY, btnW, btnH);
    
    if (self.superview != vc.view) {
        [self removeFromSuperview];
        [vc.view addSubview:self];
    }
    [vc.view bringSubviewToFront:self];
}

- (void)detach {
    [self removeFromSuperview];
    self.currentVC = nil;
}

#pragma mark - Gestures

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;
    
    CGPoint translation = [pan translationInView:superview];
    
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.lastPanPoint = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint newCenter = CGPointMake(self.lastPanPoint.x + translation.x, self.lastPanPoint.y + translation.y);
        
        // Clamp to screen bounds
        CGFloat halfW = self.bounds.size.width / 2.0;
        CGFloat halfH = self.bounds.size.height / 2.0;
        newCenter.x = MAX(halfW + 4, MIN(superview.bounds.size.width - halfW - 4, newCenter.x));
        newCenter.y = MAX(halfH + 60, MIN(superview.bounds.size.height - halfH - 60, newCenter.y));
        
        self.center = newCenter;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        // Snap to nearest screen edge
        CGFloat screenW = superview.bounds.size.width;
        CGFloat halfW = self.bounds.size.width / 2.0;
        CGFloat targetX = (self.center.x > screenW / 2.0) ? (screenW - halfW - 10.0) : (halfW + 10.0);
        
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.center = CGPointMake(targetX, self.center.y);
        } completion:nil];
        
        // Save Y position
        [[NSUserDefaults standardUserDefaults] setFloat:self.frame.origin.y forKey:kFloatingButtonYPosKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

#pragma mark - Tap & Translate

- (void)handleTap {
    UITextView *tv = [self findInputTextViewInView:self.currentVC.view ?: [UIApplication sharedApplication].keyWindow];
    NSString *currentText = tv ? tv.text : nil;
    
    if (!currentText || currentText.length == 0) {
        // Warning vibration and HUD
        AudioServicesPlaySystemSound(1521);
        [self showBriefToast:@"请先在输入框输入文字" inView:self.superview];
        return;
    }
    
    // Animate button title
    self.titleLbl.text = @"⏳...";
    
    NSString *targetLang = [WATweakSettings sharedSettings].outgoingTargetLanguage ?: @"en";
    BOOL isBilingual = [WATweakSettings sharedSettings].bilingualOutgoing;
    
    __weak typeof(self) weakSelf = self;
    [[WATranslationManager sharedManager] translateText:currentText targetLanguage:targetLang completion:^(NSString *translatedText, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            [strongSelf updateAppearance];
            
            if (translatedText && translatedText.length > 0) {
                NSString *finalText = isBilingual ? [[WATranslationManager sharedManager] formatBilingualTextWithTranslation:translatedText originalText:currentText] : translatedText;
                
                // Replace text in UITextView
                tv.text = finalText;
                if ([tv respondsToSelector:@selector(delegate)] && [tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
                    [tv.delegate textViewDidChange:tv];
                }
                
                // Success vibration
                AudioServicesPlaySystemSound(1519);
                [strongSelf showBriefToast:isBilingual ? @"已转换为双语消息" : @"已翻译为目标语言" inView:strongSelf.superview];
            } else {
                AudioServicesPlaySystemSound(1521);
                [strongSelf showBriefToast:@"翻译失败，请检查网络或配置" inView:strongSelf.superview];
            }
        });
    }];
}

#pragma mark - Long Press & Quick Menu

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self showQuickMenu];
}

- (void)showQuickMenu {
    if (!self.currentVC) return;

    AudioServicesPlaySystemSound(1519);

    WATweakSettings *settings = [WATweakSettings sharedSettings];
    NSString *bilingualTitle = settings.bilingualOutgoing ? @"✅ 双语模式: 开启 (点击关闭)" : @"⚪ 双语模式: 关闭 (点击开启)";
    NSString *outgoingTitle = settings.autoTranslateOutgoing ? @"✅ 发送时自动翻译: 开启 (点击关闭)" : @"⚪ 发送时自动翻译: 关闭 (点击开启)";
    NSString *curLangName = [WATweakSettings supportedLanguages][settings.outgoingTargetLanguage] ?: settings.outgoingTargetLanguage;
    NSString *targetLangTitle = [NSString stringWithFormat:@"🌐 发送目标语言: %@", curLangName];
    NSString *incomingTitle = settings.autoTranslateIncoming ? @"✅ 接收消息自动翻译总开关: 开启" : @"⚪ 接收消息自动翻译总开关: 关闭";

    // 按聊天开关
    NSString *chatJID = settings.currentChatJID;
    NSString *chatName = settings.currentChatName;
    BOOL chatOn = [settings shouldAutoTranslateChatJID:chatJID];
    NSString *chatLabel = [WAChatInfoResolver displayLabelForJID:chatJID ?: @"" name:chatName];
    NSString *perChatTitle;
    if (chatJID.length == 0) {
        perChatTitle = @"⚪ 本聊天自动翻译 (无法识别当前聊天)";
    } else if (chatOn) {
        perChatTitle = [NSString stringWithFormat:@"✅ 本聊天自动翻译: 开\n%@", chatLabel];
    } else {
        perChatTitle = [NSString stringWithFormat:@"⚪ 本聊天自动翻译: 关\n%@", chatLabel];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🌐 WhatsApp+ 快捷翻译" message:@"即时切换翻译模式与目标语言" preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:perChatTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (chatJID.length == 0) {
            [self showBriefToast:@"无法识别当前聊天，请先进入一个聊天" inView:self.superview];
            return;
        }
        BOOL newValue = ![settings shouldAutoTranslateChatJID:chatJID];
        [settings setAutoTranslate:newValue forChatJID:chatJID chatName:chatName];
        [settings save];
        [self updateAppearance];
        [self showBriefToast:newValue ? [NSString stringWithFormat:@"已为「%@」开启自动翻译", chatName.length ? chatName : @"本聊天"]
                                     : [NSString stringWithFormat:@"已为「%@」关闭自动翻译", chatName.length ? chatName : @"本聊天"]
                     inView:self.superview];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WATweakReloadMessagesNotification" object:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:outgoingTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        settings.autoTranslateOutgoing = !settings.autoTranslateOutgoing;
        [settings save];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:bilingualTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        settings.bilingualOutgoing = !settings.bilingualOutgoing;
        [settings save];
        [self updateAppearance];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:targetLangTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showLanguagePicker];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:incomingTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        settings.autoTranslateIncoming = !settings.autoTranslateIncoming;
        [settings save];
        [self updateAppearance];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WATweakReloadMessagesNotification" object:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 检查消息容器" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self waTweakInspectMessageContainer];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"⚙️ 打开 WhatsApp+ 全部设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        WATweakSettingsViewController *settingsVC = [[WATweakSettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self.currentVC presentViewController:nav animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = self.bounds;
    }

    [self.currentVC presentViewController:alert animated:YES completion:nil];
}

- (void)showLanguagePicker {
    if (!self.currentVC) return;
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"选择发送目标语言" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *langs = [WATweakSettings supportedLanguages];
    NSArray *sortedCodes = [[langs allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *code in sortedCodes) {
        NSString *name = langs[code];
        [actionSheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [WATweakSettings sharedSettings].outgoingTargetLanguage = code;
            [[WATweakSettings sharedSettings] save];
            [self updateAppearance];
        }]];
    }
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = self;
        actionSheet.popoverPresentationController.sourceRect = self.bounds;
    }
    [self.currentVC presentViewController:actionSheet animated:YES completion:nil];
}

#pragma mark - Helpers

- (UITextView *)findInputTextViewInView:(UIView *)parentView {
    if (!parentView) return nil;
    
    // 1. First priority: active first responder UITextView
    UITextView *firstResponderTV = [self findFirstResponderTextView:parentView];
    if (firstResponderTV) return firstResponderTV;
    
    // 2. Second priority: any UITextView in the hierarchy
    return [self findAnyTextView:parentView];
}

- (UITextView *)findFirstResponderTextView:(UIView *)view {
    if ([view isFirstResponder] && [view isKindOfClass:[UITextView class]]) {
        return (UITextView *)view;
    }
    for (UIView *sub in view.subviews) {
        UITextView *res = [self findFirstResponderTextView:sub];
        if (res) return res;
    }
    return nil;
}

- (UITextView *)findAnyTextView:(UIView *)view {
    if ([view isKindOfClass:[UITextView class]]) {
        return (UITextView *)view;
    }
    for (UIView *sub in view.subviews) {
        UITextView *res = [self findAnyTextView:sub];
        if (res) return res;
    }
    return nil;
}

- (void)showBriefToast:(NSString *)msg inView:(UIView *)targetView {
    if (!targetView) return;
    
    UILabel *toast = [[UILabel alloc] init];
    toast.text = msg;
    toast.textColor = [UIColor whiteColor];
    toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    toast.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 14.0;
    toast.layer.masksToBounds = YES;
    
    CGSize size = [msg sizeWithAttributes:@{NSFontAttributeName: toast.font}];
    CGFloat w = size.width + 30.0;
    CGFloat h = 28.0;
    toast.frame = CGRectMake((targetView.bounds.size.width - w) / 2.0, targetView.bounds.size.height - 130.0, w, h);
    toast.alpha = 0.0;
    
    [targetView addSubview:toast];
    
    [UIView animateWithDuration:0.2 animations:^{
        toast.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 delay:1.2 options:0 animations:^{
            toast.alpha = 0.0;
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    }];
}



- (void)waTweakInspectMessageContainer {
    NSMutableString *r = [NSMutableString string];
    [r appendString:@"=== 全链路检测 ===\n"];
    UIView *rootView = self.currentVC.view;
    if (!rootView) { [r appendString:@"❌ 无 currentVC.view"]; }
    else {
        CGFloat midX = CGRectGetWidth(rootView.bounds) / 2.0;
        // ① 找容器
        Class containerClass = NSClassFromString(@"WAMessageContainerView");
        NSMutableArray *found = [NSMutableArray array];
        __block void (^findInner)(UIView *, int);
        findInner = ^(UIView *v, int depth) {
            if (!v || depth > 12 || found.count >= 5) return;
            if (containerClass && [v isKindOfClass:containerClass]) [found addObject:v];
            for (UIView *sub in v.subviews) findInner(sub, depth + 1);
        };
        findInner(rootView, 0);
        [r appendFormat:@"① 容器: %@ (%lu个)\n", found.count > 0 ? @"✅" : @"❌", (unsigned long)found.count];
        if (found.count == 0) {
            [r appendString:@"\n结论: 找不到消息容器，扫描器无法工作\n"];
        } else {
            UIView *container = found[0];
            // ② sliceViews
            NSArray *slices = nil;
            @try { slices = [container valueForKey:@"sliceViews"]; } @catch (NSException *e) {}
            BOOL slicesOK = [slices isKindOfClass:[NSArray class]] && slices.count > 0;
            [r appendFormat:@"② sliceViews: %@ (%lu个)\n", slicesOK ? @"✅" : @"❌", (unsigned long)([slices isKindOfClass:[NSArray class]] ? slices.count : 0)];
            // ③ 找文本 slice
            UIView *textSlice = nil;
            if (slicesOK) {
                for (id s in slices) {
                    NSString *sc = NSStringFromClass([s class]);
                    if ([sc rangeOfString:@"AttributedText"].location != NSNotFound && [s isKindOfClass:[UIView class]]) {
                        textSlice = (UIView *)s;
                        [r appendFormat:@"③ 文本slice: ✅ %@\n", sc];
                        break;
                    }
                }
                if (!textSlice) [r appendString:@"③ 文本slice: ❌ 未找到\n"];
            }
            // ④ 读 attributedText
            NSAttributedString *origAttr = nil;
            NSString *text = nil;
            if (textSlice) {
                @try { origAttr = [textSlice valueForKey:@"attributedText"]; } @catch (NSException *e) {}
                BOOL attrOK = [origAttr isKindOfClass:[NSAttributedString class]];
                [r appendFormat:@"④ 读attributedText: %@\n", attrOK ? @"✅" : @"❌"];
                if (attrOK) {
                    text = origAttr.string;
                    NSString *preview = text.length > 30 ? [[text substringToIndex:30] stringByAppendingString:@"…"] : text;
                    [r appendFormat:@"⑤ 文本内容: ✅ \"%@\" (长%lu)\n", preview, (unsigned long)text.length];
                    BOOL alreadyBi = [text containsString:@"──────────"];
                    [r appendFormat:@"   已双语: %@\n", alreadyBi ? @"是(会跳过)" : @"否"];
                } else {
                    [r appendString:@"⑤ 文本内容: ❌\n"];
                }
            }
            // ⑥ cellData
            id cellData = nil;
            @try { cellData = [container valueForKey:@"cellData"]; } @catch (NSException *e) {}
            [r appendFormat:@"⑥ cellData: %@ %@\n", cellData ? @"✅" : @"❌", cellData ? NSStringFromClass([cellData class]) : @""];
            // ⑦ message
            id message = nil;
            if (cellData) {
                @try { message = [cellData valueForKey:@"message"]; } @catch (NSException *e) {}
            }
            [r appendFormat:@"⑦ message: %@\n", message ? @"✅" : @"❌"];
            // ⑧ fromMe
            NSString *dirResult = @"❌ 取不到";
            BOOL isFromMe = NO;
            BOOL hasDir = NO;
            if (message) {
                id v = nil;
                @try { v = [message valueForKey:@"fromMe"]; } @catch (NSException *e1) {
                    @try { v = [message valueForKey:@"isFromMe"]; } @catch (NSException *e2) {}
                }
                if ([v isKindOfClass:[NSNumber class]]) {
                    isFromMe = [v boolValue];
                    hasDir = YES;
                    dirResult = isFromMe ? @"✅ 是自己的(应跳过)" : @"✅ 是对方的(应翻译)";
                }
            }
            [r appendFormat:@"⑧ 方向(fromMe): %@\n", dirResult];
            // ⑨ 位置
            CGRect cf = [container convertRect:container.bounds toView:rootView];
            BOOL posIncoming = CGRectGetMinX(cf) <= midX * 0.6;
            [r appendFormat:@"⑨ 位置: minX=%.0f, 阈值=%.0f → %@\n", CGRectGetMinX(cf), midX * 0.6, posIncoming ? @"✅ 对方(左)" : @"❌ 自己(右)"];
            // ⑩ 写入测试
            if (textSlice && origAttr) {
                BOOL writeOK = NO;
                @try {
                    NSAttributedString *testAttr = [[NSAttributedString alloc] initWithString:origAttr.string attributes:[origAttr attributesAtIndex:0 effectiveRange:NULL]];
                    [textSlice setValue:testAttr forKey:@"attributedText"];
                    // 读回验证
                    NSAttributedString *back = [textSlice valueForKey:@"attributedText"];
                    // 恢复原文
                    [textSlice setValue:origAttr forKey:@"attributedText"];
                    writeOK = [back isKindOfClass:[NSAttributedString class]];
                } @catch (NSException *e) {
                    writeOK = NO;
                }
                [r appendFormat:@"⑩ 写入测试: %@\n", writeOK ? @"✅ 可写回" : @"❌ 写失败"];
            } else {
                [r appendString:@"⑩ 写入测试: ❌ 无slice\n"];
            }
            // 结论
            [r appendString:@"\n=== 结论 ===\n"];
            if (textSlice && text && text.length >= 2 && ![text containsString:@"──────────"]) {
                if ((hasDir && !isFromMe) || (!hasDir && posIncoming)) {
                    [r appendString:@"链路全通，应能翻译。若仍无双语，可能是翻译请求失败。"];
                } else {
                    [r appendString:@"方向判断为自己消息，会被跳过。检查fromMe/位置逻辑。"];
                }
            } else {
                [r appendString:@"文本获取失败，无法翻译。"];
            }
        }
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"全链路检测" message:r preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
    [self.currentVC presentViewController:alert animated:YES completion:nil];
}

@end
