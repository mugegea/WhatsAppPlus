#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WAFloatingTranslateButton : UIButton

+ (instancetype)sharedButton;

/**
 * Attaches the floating button to the specified chat view controller.
 */
- (void)attachToViewController:(UIViewController *)vc;

/**
 * Detaches the floating button when leaving the chat.
 */
- (void)detach;

/**
 * Updates button label and appearance based on current settings.
 */
- (void)updateAppearance;

/**
 * Tap action to translate active input text view.
 */
- (void)handleTap;

/**
 * Long press action to display quick menu.
 */
- (void)handleLongPress:(nullable UILongPressGestureRecognizer *)gesture;

/**
 * Show the quick menu directly (used by the [文/A] nav button).
 */
- (void)showQuickMenu;

/**
 * Brief toast message in a view.
 */
- (void)showBriefToast:(NSString *)message inView:(nullable UIView *)view;

@end

NS_ASSUME_NONNULL_END
