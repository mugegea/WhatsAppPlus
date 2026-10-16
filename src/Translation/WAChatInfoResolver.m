#import "WAChatInfoResolver.h"

@implementation WAChatInfoResolver

#pragma mark - Public

+ (NSString *)chatJIDForViewController:(UIViewController *)vc {
    if (!vc) return nil;

    // 1) 先从 VC 身上找会话对象（键名按常见度排序，全部防御性读取）
    NSArray<NSString *> *sessionKeys = @[@"chatSession", @"session", @"conversation", @"chat", @"chatContext"];
    for (NSString *key in sessionKeys) {
        id session = nil;
        @try {
            session = [vc valueForKey:key];
        } @catch (NSException *exception) {
            continue;
        }
        NSString *jid = [self jidFromSessionObject:session];
        if (jid.length > 0) return jid;
    }

    // 2) 兜底：VC 自身是否直接带 jid
    for (NSString *key in @[@"jid", @"chatJID", @"peerJID"]) {
        @try {
            NSString *jid = [self jidFromObject:[vc valueForKey:key]];
            if (jid.length > 0) return jid;
        } @catch (NSException *exception) {
            continue;
        }
    }
    return nil;
}

+ (NSString *)chatIdentifierForViewController:(UIViewController *)vc {
    NSString *jid = [self chatJIDForViewController:vc];
    if (jid.length > 0) return jid;
    NSString *name = [self chatNameForViewController:vc];
    if (name.length > 0) return [@"name:" stringByAppendingString:name];
    return nil;
}

+ (NSString *)chatIdentifierForMessage:(id)message {
    if (!message) return nil;
    // 消息对象自带的会话引用（键名按常见度排序，防御性读取）
    for (NSString *key in @[@"chatSession", @"session", @"conversation", @"chat"]) {
        id session = nil;
        @try {
            session = [message valueForKey:key];
        } @catch (NSException *exception) {
            continue;
        }
        NSString *jid = [self jidFromSessionObject:session];
        if (jid.length > 0) return jid;
    }
    return nil;
}

+ (BOOL)isNameBasedKey:(NSString *)key {
    return key.length > 0 && [key hasPrefix:@"name:"];
}

+ (NSString *)chatNameForViewController:(UIViewController *)vc {
    if (!vc) return nil;
    NSString *title = nil;
    @try {
        title = vc.navigationItem.title;
        if (title.length == 0) title = vc.title;
    } @catch (NSException *exception) {
        title = nil;
    }
    title = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return title.length > 0 ? title : nil;
}

+ (BOOL)isGroupJID:(NSString *)jid {
    return jid.length > 0 && [jid hasSuffix:@"@g.us"];
}

+ (BOOL)isIndividualJID:(NSString *)jid {
    return jid.length > 0 && [jid hasSuffix:@"@s.whatsapp.net"];
}

+ (NSString *)displayLabelForJID:(NSString *)jid name:(NSString *)name {
    // 名称兜底型 key：直接显示名称
    if ([self isNameBasedKey:jid]) {
        NSString *n = [jid substringFromIndex:5];
        if (n.length > 0) return n;
    }
    NSString *base = name.length > 0 ? name : jid;
    if ([self isGroupJID:jid]) {
        return [NSString stringWithFormat:@"%@ · 群聊", base];
    }
    if ([self isIndividualJID:jid]) {
        // 个人聊天：名字后面跟脱敏号码
        NSString *number = [[jid componentsSeparatedByString:@"@"].firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (number.length > 4 && ![base isEqualToString:jid]) {
            NSString *masked = [NSString stringWithFormat:@"***%@", [number substringFromIndex:number.length - 4]];
            return [NSString stringWithFormat:@"%@ (%@)", base, masked];
        }
    }
    return base;
}

#pragma mark - Private

/// 从会话对象里挖 JID（支持 NSString / JID 模型对象 / 嵌套一层）
+ (NSString *)jidFromSessionObject:(id)session {
    if (!session || session == (id)[NSNull null]) return nil;

    // 会话对象本身可能就是 JID 字符串
    NSString *direct = [self jidFromObject:session];
    if (direct.length > 0) return direct;

    // 常见属性名
    for (NSString *key in @[@"jid", @"chatJID", @"peerJID", @"remoteJID", @"recipientJID", @"toJID"]) {
        id value = nil;
        @try {
            value = [session valueForKey:key];
        } @catch (NSException *exception) {
            continue;
        }
        NSString *jid = [self jidFromObject:value];
        if (jid.length > 0) return jid;
    }

    // 嵌套一层：session.chat.jid 之类
    for (NSString *key in @[@"chat", @"conversation", @"context"]) {
        id nested = nil;
        @try {
            nested = [session valueForKey:key];
        } @catch (NSException *exception) {
            continue;
        }
        if (nested && nested != session) {
            NSString *jid = [self jidFromSessionObject:nested];
            if (jid.length > 0) return jid;
        }
    }
    return nil;
}

/// 把任意对象规整成 JID 字符串；不是合法 JID 返回 nil
+ (NSString *)jidFromObject:(id)obj {
    if (!obj || obj == (id)[NSNull null]) return nil;

    if ([obj isKindOfClass:[NSString class]]) {
        return [self validatedJID:(NSString *)obj];
    }

    // JID 模型对象：尝试常见取值方式
    for (NSString *key in @[@"stringValue", @"fullJID", @"jidString"]) {
        @try {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id value = [obj performSelector:NSSelectorFromString(key)];
#pragma clang diagnostic pop
                NSString *jid = [self validatedJID:value];
                if (jid.length > 0) return jid;
            }
        } @catch (NSException *exception) {
            continue;
        }
    }

    // 最后手段：description（XMPPJID 的 description 通常就是 JID 本体）
    @try {
        NSString *desc = [obj description];
        NSString *jid = [self validatedJID:desc];
        if (jid.length > 0) return jid;
    } @catch (NSException *exception) {}
    return nil;
}

/// 合法性校验：必须含 @ 且后缀是已知的 WhatsApp 域
+ (NSString *)validatedJID:(id)candidate {
    if (![candidate isKindOfClass:[NSString class]]) return nil;
    NSString *s = [(NSString *)candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0 || [s rangeOfString:@"@"].location == NSNotFound) return nil;
    // 取第一段（去掉可能的参数后缀）
    NSString *bare = [[s componentsSeparatedByString:@" "] firstObject];
    if ([bare hasSuffix:@"@s.whatsapp.net"] || [bare hasSuffix:@"@g.us"] ||
        [bare hasSuffix:@"@broadcast"] || [bare hasSuffix:@"@lid"]) {
        return bare;
    }
    return nil;
}

@end
