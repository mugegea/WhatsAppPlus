#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 从聊天 ViewController / 消息对象里防御性地解析聊天标识。
 *
 * WhatsApp 内部类名/属性名随版本变化，这里不做任何硬假设：
 * 所有 KVC 读取都用 @try/@catch 包裹，解析失败返回 nil，调用方必须处理 nil。
 *
 * 聊天标识（chat key）优先用 JID：
 *   个人聊天： "1234567890@s.whatsapp.net"
 *   群聊：     "1234567890-1234567890@g.us"
 * JID 解析失败时降级用聊天名称："name:<标题>"（保证按聊天开关可用）。
 */
@interface WAChatInfoResolver : NSObject

/// 解析当前聊天的 JID，失败返回 nil
+ (nullable NSString *)chatJIDForViewController:(nullable UIViewController *)vc;

/// 聊天标识：JID 优先，取不到则用 "name:<标题>" 兜底，都取不到返回 nil
+ (nullable NSString *)chatIdentifierForViewController:(nullable UIViewController *)vc;

/// 从消息对象自带的会话信息解析聊天标识（JID 优先），失败返回 nil
+ (nullable NSString *)chatIdentifierForMessage:(nullable id)message;

/// 解析当前聊天的显示名称（优先导航栏标题），失败返回 nil
+ (nullable NSString *)chatNameForViewController:(nullable UIViewController *)vc;

/// 是否为群聊 JID
+ (BOOL)isGroupJID:(nullable NSString *)jid;

/// 是否为个人聊天 JID
+ (BOOL)isIndividualJID:(nullable NSString *)jid;

/// 给设置界面用的展示串，例如 "张三 · 群聊" / "1234567890"；name: 开头的 key 直接显示名称
+ (NSString *)displayLabelForJID:(NSString *)jid name:(nullable NSString *)name;

/// 聊天标识是否为名称兜底型（"name:" 前缀）
+ (BOOL)isNameBasedKey:(nullable NSString *)key;

@end

NS_ASSUME_NONNULL_END
