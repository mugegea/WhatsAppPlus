#pragma once

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

@class WATranslationManager;

#define TWEAK_NAME @"WhatsAppPlus"
#define TWEAK_VERSION @"1.0.1"
#define TWEAK_AUTHOR @"@bengege"
#define TWEAK_TELEGRAM @"https://t.me/bengege"

#ifdef DEBUG
    #define WALog(fmt, ...) NSLog(@"[%@] " fmt, TWEAK_NAME, ##__VA_ARGS__)
#else
    #define WALog(fmt, ...) ((void)0)
#endif

// Forward declarations of WhatsApp internal classes
@class WAMessage, WAChatStorage, WAChatBar;
@class WAMessageCell, WAMessagePresenter, WAChatSession, WAMessageContainerView;

@interface WAChatViewController : UIViewController
@property (nonatomic, strong) UITableView *tableView;
- (void)waTweak_reloadMessagesSafely;
- (BOOL)waTweak_reloadAllScrollViews:(UIView *)view;
- (BOOL)waTweak_reloadAllScrollViews:(UIView *)view depth:(int)depth;
- (BOOL)waTweak_isMenuShowing;
- (void)waTweak_setupNavTranslateButton;
- (void)waTweak_showQuickTranslationMenu;
- (void)waTweak_updateCurrentChatIdentity;
- (void)waTweak_startLabelScanTimer;
- (void)waTweak_stopLabelScanTimer;
- (void)waTweak_scanAndTranslateLabels;
- (void)waTweak_scanView:(UIView *)view depth:(int)depth midX:(CGFloat)midX chatView:(UIView *)chatView;
- (void)waTweak_processMessageContainer:(UIView *)container midX:(CGFloat)midX chatView:(UIView *)chatView;
- (void)waTweak_addTranslationOverlay:(NSString *)translation forContainer:(UIView *)container originalText:(NSString *)origText;
- (void)waTweak_positionOverlay:(UILabel *)overlay forContainer:(UIView *)container;
- (void)waTweak_processMessageTextView:(UIView *)view midX:(CGFloat)midX chatView:(UIView *)chatView;
- (void)waTweak_translateTextView:(UIView *)view originalText:(NSString *)text;
- (BOOL)waTweak_isUserInteracting;
- (void)waTweak_enumerateScrollViews:(UIView *)view depth:(int)depth block:(void (^)(UIScrollView *))block;
@end

@interface WASettingsViewController : UIViewController
- (void)waTweak_openSettings;
- (void)waTweak_openIconPicker;
@end

@interface WAMessage : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *toJID;
@property (nonatomic, copy) NSString *fromJID;
@property (nonatomic, assign) BOOL isRevoked;
@property (nonatomic, assign) BOOL isFromMe;
@property (nonatomic, readonly) NSString *stanzaID;
@property (nonatomic, readonly) NSString *uniqueIdentifier;
@property (nonatomic, readonly) NSDate *messageDate;
@property (nonatomic, readonly) int64_t messageType;
@end

@interface WAChatStorage : NSObject
+ (instancetype)sharedManager;
- (void)revokeMessages:(NSArray *)messages;
- (void)revokeMessage:(WAMessage *)message;
- (void)markMessagesAsRevoked:(NSArray *)messages;
@end

@interface WAChatBar : UIView
@property (nonatomic, strong) UITextView *inputTextView;
@property (nonatomic, copy) NSString *text;
- (void)sendTextMessage:(NSString *)text;
- (void)sendButtonTapped:(id)sender;
- (void)didMoveToWindow; // 显式声明，避免 Logos 误报 new method
- (UITextView *)waTweak_findInputTextView;
- (void)waTweak_setupEagerTranslation;
- (void)waTweak_inputTextDidChange:(NSNotification *)note;
- (void)waTweak_scheduleEagerTranslation;
- (void)waTweak_doEagerTranslation;
- (void)waTweak_applyEagerTranslation:(NSString *)translated originalText:(NSString *)original expectedCurrent:(NSString *)expected;
@end

// 启动自诊断报告（Tweak.x 实现）
NSString *waTweakDiagnosticReport(void);
// -text / -richText / -richTextFromMessage / -setText: hook 调用计数（Tweak.x 实现）
int64_t waTweakTextHookCountValue(void);
int64_t waTweakRichTextHookCountValue(void);
int64_t waTweakRichTextFromMsgHookCountValue(void);
int64_t waTweakSetTextHookCountValue(void);
// Label 扫描器计数（Tweak.x 实现）
