#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "AxsTwinDialConfig.h"
#import "AxsTwinDialView.h"

static AxsTwinDialView *AxsTwinDialDesktop;
static NSTimer *AxsTwinDialDesktopTimer;
static BOOL AxsTwinDialCoverTransition;
static BOOL AxsTwinDialControllerAppeared = YES;

static id axs_twindial_object(id object, SEL op) {
    if (![object respondsToSelector:op]) return nil;
    NSMethodSignature *sig = [object methodSignatureForSelector:op];
    if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, op);
}

static BOOL axs_twindial_bool(id object, SEL op, BOOL fallback) {
    if (![object respondsToSelector:op]) return fallback;
    NSMethodSignature *sig = [object methodSignatureForSelector:op];
    if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(BOOL))) return fallback;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, op);
}

static UIView *axs_twindial_desktopHost(void) {
    if (AxsTwinDialCoverTransition || !AxsTwinDialControllerAppeared) return nil;
    UIApplication *springboard = UIApplication.sharedApplication;
    if (!axs_twindial_bool(springboard, @selector(isShowingHomescreen), NO)) return nil;
    id lock = axs_twindial_object(NSClassFromString(@"SBLockScreenManager"), @selector(sharedInstance));
    if (axs_twindial_bool(lock, @selector(isUILocked), YES) || axs_twindial_bool(lock, @selector(isLockScreenVisible), YES)) return nil;
    for (UIScene *scene in springboard.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in [(UIWindowScene *)scene windows]) {
            if (!w.hidden && w.alpha > .01 && [w isKindOfClass:NSClassFromString(@"SBMainSwitcherWindow")]) return nil;
        }
    }
    id icons = axs_twindial_object(NSClassFromString(@"SBIconController"), @selector(sharedInstance));
    if (axs_twindial_bool(icons, @selector(isEditing), YES)) return nil;
    id controller = axs_twindial_object(icons, @selector(_rootFolderController));
    id root = axs_twindial_object(controller, @selector(rootFolderView));
    id list = axs_twindial_object(root, @selector(currentIconListView));
    id lists = axs_twindial_object(root, @selector(iconListViews));
    if (![lists isKindOfClass:NSArray.class] || ![lists containsObject:list ?: NSNull.null] || ![list isKindOfClass:UIView.class]) return nil;
    id firstOnly = [[AxsTwinDialConfig axs_twindial_shared] axs_twindial_valueForKey:@"firstPageOnly" defaultValue:@YES];
    if (![firstOnly isKindOfClass:NSNumber.class] || [firstOnly boolValue]) {
        id first = axs_twindial_object(root, @selector(firstIconListView)) ?: [lists firstObject];
        if (list != first) return nil;
    }
    id location = axs_twindial_object(list, @selector(iconLocation));
    if (![location isKindOfClass:NSString.class] || ![location hasPrefix:@"SBIconLocationRoot"]) return nil;
    UIView *host = list;
    UIWindow *window = host.window;
    if (!window || window.screen != UIScreen.mainScreen || window.windowScene.activationState == UISceneActivationStateBackground) return nil;
    for (UIView *view = host; view; view = view.superview) if (view.hidden || view.alpha < .05) return nil;
    CGRect projected = [host convertRect:host.bounds toView:window];
    CGRect visible = CGRectIntersection(projected,window.bounds);
    if (CGRectIsEmpty(visible) || CGRectGetWidth(visible) < CGRectGetWidth(projected)*.97) return nil;
    for (UIView *view = host.superview; view; view = view.superview) {
        if ([view isKindOfClass:UIScrollView.class] && ([(UIScrollView *)view isDragging] || [(UIScrollView *)view isDecelerating])) return nil;
    }
    return host;
}

static void axs_twindial_updateDesktop(void) {
    UIView *host = [[AxsTwinDialConfig axs_twindial_shared] axs_twindial_isEnabled] ? axs_twindial_desktopHost() : nil;
    if (!host) {
        [AxsTwinDialDesktop axs_twindial_setRunning:NO];
        [AxsTwinDialDesktop removeFromSuperview];
        return;
    }
    if (!AxsTwinDialDesktop) AxsTwinDialDesktop = [[AxsTwinDialView alloc] initWithFrame:host.bounds];
    if (AxsTwinDialDesktop.superview != host) {
        [AxsTwinDialDesktop removeFromSuperview];
        AxsTwinDialDesktop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        AxsTwinDialDesktop.frame = host.bounds;
        [host addSubview:AxsTwinDialDesktop];
    }
    [AxsTwinDialDesktop axs_twindial_setRunning:YES];
}

static void axs_twindial_updateSettings(void) {
    [AxsTwinDialDesktop axs_twindial_reloadStyle];
    BOOL enabled = [[AxsTwinDialConfig axs_twindial_shared] axs_twindial_isEnabled];
    if (enabled && !AxsTwinDialDesktopTimer) {
        AxsTwinDialDesktopTimer = [NSTimer timerWithTimeInterval:.65 repeats:YES block:^(NSTimer *timer) { axs_twindial_updateDesktop(); }];
        [NSRunLoop.mainRunLoop addTimer:AxsTwinDialDesktopTimer forMode:NSDefaultRunLoopMode];
    } else if (!enabled) {
        [AxsTwinDialDesktopTimer invalidate]; AxsTwinDialDesktopTimer = nil;
    }
    axs_twindial_updateDesktop();
}

%group AxsTwinDialDesktopHooks
%hook SBIconController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    AxsTwinDialControllerAppeared = YES;
    axs_twindial_updateDesktop();
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    AxsTwinDialControllerAppeared = NO;
    axs_twindial_updateDesktop();
}
%end
%hook SBMainSwitcherWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    axs_twindial_updateDesktop();
}
%end
%end

%ctor {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 16 ||
        ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    %init(AxsTwinDialDesktopHooks);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:@"com.axs.twindial.preferences-changed" object:nil queue:nil usingBlock:^(NSNotification *note) { axs_twindial_updateSettings(); }];
        [center addObserverForName:@"SBCoverSheetWillPresentNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { AxsTwinDialCoverTransition = YES; axs_twindial_updateDesktop(); }];
        [center addObserverForName:@"SBCoverSheetDidDismissNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { AxsTwinDialCoverTransition = NO; axs_twindial_updateDesktop(); }];
        axs_twindial_updateSettings();
    });
}
