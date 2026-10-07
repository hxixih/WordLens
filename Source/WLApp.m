#import "WLApp.h"
#import "WLCompatibility.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/QuartzCore.h>

static NSColor *WLBlue(void) { return [NSColor colorWithSRGBRed:0.20 green:0.34 blue:0.92 alpha:1]; }
static NSTextField *WLLabel(NSString *text, CGFloat size, BOOL bold) {
    NSTextField *v=[NSTextField labelWithString:text];
    v.font=bold ? [NSFont systemFontOfSize:size weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:size];
    v.textColor=NSColor.labelColor; return v;
}
static NSButton *WLButton(NSString *text,id target,SEL action) {
    NSButton *b=[NSButton buttonWithTitle:text target:target action:action];
    b.bezelStyle=NSBezelStyleRounded; b.font=[NSFont systemFontOfSize:13]; return b;
}
static NSImage *WLLogo(CGFloat size, BOOL template) {
    NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(size,size)]; [image lockFocus];
    NSRect r=NSMakeRect(size*.08,size*.08,size*.84,size*.84);
    [template ? NSColor.blackColor : WLBlue() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:r xRadius:size*.23 yRadius:size*.23] fill];
    NSMutableParagraphStyle *p=[NSMutableParagraphStyle new]; p.alignment=NSTextAlignmentCenter;
    [@"译" drawInRect:NSMakeRect(0,size*.16,size,size*.72) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size*.55 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.whiteColor,NSParagraphStyleAttributeName:p}];
    [image unlockFocus]; image.template=template; return image;
}

@interface WLTextView : NSTextView
@property(nonatomic, copy) NSString *placeholder;
@end
@implementation WLTextView
- (void)drawRect:(NSRect)dirtyRect { [super drawRect:dirtyRect]; if (!self.string.length && self.placeholder.length) [self.placeholder drawInRect:NSInsetRect(self.bounds,16,14) withAttributes:@{NSFontAttributeName:self.font ?: [NSFont systemFontOfSize:16],NSForegroundColorAttributeName:NSColor.placeholderTextColor}]; }
@end

@interface WLFlippedView : NSView
@end
@implementation WLFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface WLMainView : WLFlippedView
@property(nonatomic,strong) NSTextField *titleLabel,*subtitle,*sourceLabel,*resultLabel,*counter,*status,*footer;
@property(nonatomic,strong) NSButton *settingsButton,*translateButton,*cancelButton,*sourceCopyButton,*resultCopyButton,*clipboard;
@property(nonatomic,strong) NSScrollView *sourceScroll,*resultScroll;
@property(nonatomic,strong) NSProgressIndicator *spinner;
@end
@implementation WLMainView
- (void)layout {
    [super layout]; CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    _titleLabel.frame=NSMakeRect(24,17,w-270,28);
    _subtitle.frame=NSMakeRect(24,48,w-250,20);
    _settingsButton.frame=NSMakeRect(w-91,22,68,30);
    _clipboard.frame=NSMakeRect(w-225,22,127,30);
    _sourceLabel.frame=NSMakeRect(24,94,110,24);
    _counter.frame=NSMakeRect(132,99,w-385,20);
    _sourceCopyButton.frame=NSMakeRect(w-218,90,86,30);
    _translateButton.frame=NSMakeRect(w-125,90,101,30);
    CGFloat sh=floor((h-256)*.43);
    _sourceScroll.frame=NSMakeRect(24,130,w-48,sh);
    CGFloat y=130+sh+25;
    _resultLabel.frame=NSMakeRect(24,y,130,24);
    _resultCopyButton.frame=NSMakeRect(w-125,y-4,101,30);
    _resultScroll.frame=NSMakeRect(24,y+36,w-48,h-y-122);
    _spinner.frame=NSMakeRect(25,h-72,16,16);
    _status.frame=NSMakeRect(49,h-74,w-177,38);
    _cancelButton.frame=NSMakeRect(w-108,h-76,86,30);
    _footer.frame=NSMakeRect(24,h-28,w-48,18);
}
@end

@interface WLBubble : NSPanel
@end
@implementation WLBubble
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface WLAppDelegate ()
@property(nonatomic,strong) WLSettings *settings;
@property(nonatomic,strong) WLClient *client;
@property(nonatomic,strong) NSWindow *mainWindow,*settingsWindow;
@property(nonatomic,strong) WLMainView *mainView;
@property(nonatomic,strong) WLTextView *sourceText,*resultText;
@property(nonatomic,strong) NSStatusItem *statusItem;
@property(nonatomic,strong) WLBubble *bubble;
@property(nonatomic,strong) id mouseMonitor,keyMonitor,localMonitor,workspaceObserver;
@property(nonatomic,strong) NSTimer *bubbleTimer,*permissionTimer;
@property(nonatomic,strong) NSURLSessionDataTask *translationTask,*testTask;
@property(nonatomic) NSUInteger translationGeneration,testGeneration;
@property(atomic) NSUInteger selectionGeneration;
@property(nonatomic,copy) NSString *pendingSelection;
@property(nonatomic) pid_t pendingPID,mouseDownPID;
@property(nonatomic) NSPoint mouseDownPoint;
@property(nonatomic) BOOL mouseDragged,shortcutKeyReleaseExpected;
@property(nonatomic,strong) WLCopyCapture *selectionCopier;
@property(nonatomic,strong) dispatch_queue_t selectionQueue;
@property(nonatomic,strong) NSTextField *baseField,*modelField,*timeoutField,*settingsStatus,*permissionLabel;
@property(nonatomic,strong) NSSecureTextField *keyField;
@property(nonatomic,strong) NSButton *autoCheckbox,*monitorCheckbox,*fallbackCheckbox,*testButton;
@property(nonatomic,strong) NSMenuItem *pauseItem;
@property(nonatomic) BOOL baseKeyLoadFailed;
@property(nonatomic,copy) NSString *loadedKeyEndpoint;
@property(nonatomic) EventHotKeyRef hotkey;
@property(nonatomic) EventHandlerRef hotkeyHandler;
@end

static OSStatus WLHotkeyHandler(EventHandlerCallRef next, EventRef event, void *data) {
    WLAppDelegate *app=(__bridge WLAppDelegate *)data;
    [app performSelector:@selector(translateSelectionShortcut:) withObject:nil]; return noErr;
}

@implementation WLAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.settings=[WLSettings new]; self.client=[WLClient new];
    self.selectionCopier=[[WLCopyCapture alloc] initWithClipboard:[[WLPasteboard alloc] initWithPasteboard:NSPasteboard.generalPasteboard] frontPID:^pid_t { return NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier; } sendCopy:^BOOL(pid_t pid) { return WLSendCopyToPID(pid); }];
    self.selectionQueue=dispatch_queue_create("cn.local.WordLens.selection",DISPATCH_QUEUE_SERIAL);
    [self buildMenus]; [self buildMainWindow]; [self buildBubble]; [self installMonitors];
    [[NSWorkspace sharedWorkspace].notificationCenter addObserver:self selector:@selector(frontAppChanged:) name:NSWorkspaceDidActivateApplicationNotification object:nil];
    EventTypeSpec type={kEventClassKeyboard,kEventHotKeyPressed};
    InstallApplicationEventHandler(WLHotkeyHandler,1,&type,(__bridge void *)self,&_hotkeyHandler);
    EventHotKeyID hotkeyID={'WLen',1};
    OSStatus status=RegisterEventHotKey(kVK_ANSI_T,cmdKey|optionKey,hotkeyID,GetApplicationEventTarget(),0,&_hotkey);
    [self openMain:nil];
    if (status!=noErr) [self setStatus:@"快捷键 ⌥⌘T 已被其他程序占用，可用菜单栏入口。" error:YES];
    else [self setStatus:AXIsProcessTrusted() ? @"准备就绪：选中文字，点击浮动「译」图标。" : @"首次使用：点击「设置」，开启辅助功能并填写模型参数。" error:NO];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible { [self openMain:nil]; return YES; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    for (id token in @[_mouseMonitor ?: NSNull.null,_keyMonitor ?: NSNull.null,_localMonitor ?: NSNull.null]) if (token!=NSNull.null) [NSEvent removeMonitor:token];
    if (_hotkey) UnregisterEventHotKey(_hotkey);
    if (_hotkeyHandler) RemoveEventHandler(_hotkeyHandler);
    [_translationTask cancel]; [_testTask cancel]; [_client.session invalidateAndCancel];
    [_selectionCopier cancel];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}
- (void)buildMenus {
    NSMenu *menu=[NSMenu new]; NSMenuItem *appItem=[NSMenuItem new]; [menu addItem:appItem];
    NSMenu *appMenu=[[NSMenu alloc] initWithTitle:@"划词译"];
    NSMenuItem *settings=[[NSMenuItem alloc] initWithTitle:@"设置…" action:@selector(openSettings:) keyEquivalent:@","]; settings.target=self; [appMenu addItem:settings];
    [appMenu addItem:NSMenuItem.separatorItem]; [appMenu addItemWithTitle:@"退出划词译" action:@selector(terminate:) keyEquivalent:@"q"]; appItem.submenu=appMenu;
    NSMenuItem *editItem=[[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""]; [menu addItem:editItem];
    NSMenu *edit=[[NSMenu alloc] initWithTitle:@"编辑"];
    [edit addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"]; editItem.submenu=edit; NSApp.mainMenu=menu;
    _statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    // Use plain glyph for a crisp monochrome menu bar mark on older macOS.
    _statusItem.button.title=@"译"; _statusItem.button.font=[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold]; _statusItem.button.toolTip=@"划词译 · ⌥⌘T";
    NSMenu *tray=[NSMenu new];
    for (NSArray *entry in @[@[@"打开翻译窗口",NSStringFromSelector(@selector(openMain:))],@[@"翻译剪贴板",NSStringFromSelector(@selector(translateClipboard:))],@[@"翻译所选文字  ⌥⌘T",NSStringFromSelector(@selector(translateSelectionShortcut:))],@[@"设置…",NSStringFromSelector(@selector(openSettings:))]]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""]; item.target=self; [tray addItem:item];
    }
    [tray addItem:NSMenuItem.separatorItem];
    _pauseItem=[[NSMenuItem alloc] initWithTitle:@"启用划词图标" action:@selector(toggleMonitor:) keyEquivalent:@""]; _pauseItem.target=self; [tray addItem:_pauseItem];
    [tray addItem:NSMenuItem.separatorItem]; [tray addItemWithTitle:@"退出划词译" action:@selector(terminate:) keyEquivalent:@""];
    _statusItem.menu=tray; [self refreshPauseMenu];
}
- (NSScrollView *)scrollForText:(WLTextView **)out editable:(BOOL)editable placeholder:(NSString *)placeholder {
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,560,180)]; scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES;
    scroll.borderType=NSNoBorder; scroll.drawsBackground=YES; scroll.backgroundColor=NSColor.textBackgroundColor;
    scroll.wantsLayer=YES; scroll.layer.cornerRadius=12; scroll.layer.borderWidth=1;
    scroll.layer.borderColor=[NSColor colorWithWhite:.72 alpha:.35].CGColor; scroll.layer.masksToBounds=YES;
    WLTextView *text=[[WLTextView alloc] initWithFrame:NSMakeRect(0,0,560,180)];
    text.minSize=NSMakeSize(0,180); text.maxSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
    text.verticallyResizable=YES; text.horizontallyResizable=NO; text.autoresizingMask=NSViewWidthSizable;
    text.textContainer.containerSize=NSMakeSize(560,CGFLOAT_MAX); text.textContainer.widthTracksTextView=YES;
    text.textContainerInset=NSMakeSize(12,14); text.font=[NSFont systemFontOfSize:editable ? 16 : 17];
    text.richText=NO; text.editable=editable; text.selectable=YES; text.allowsUndo=editable;
    text.automaticQuoteSubstitutionEnabled=NO; text.automaticDashSubstitutionEnabled=NO; text.automaticSpellingCorrectionEnabled=NO;
    text.textColor=NSColor.textColor; text.backgroundColor=NSColor.textBackgroundColor; text.placeholder=placeholder;
    text.accessibilityLabel=editable ? @"待翻译原文" : @"中文译文";
    scroll.documentView=text; *out=text; return scroll;
}
- (void)buildMainWindow {
    if (!_settings) _settings=[WLSettings new];
    _mainWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,650) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    _mainWindow.title=@"划词译 · WordLens"; _mainWindow.minSize=NSMakeSize(560,540); _mainWindow.releasedWhenClosed=NO; _mainWindow.delegate=self;
    [_mainWindow setFrameAutosaveName:@"WordLens.Main"]; [_mainWindow center];
    WLMainView *v=[[WLMainView alloc] initWithFrame:NSMakeRect(0,0,650,650)]; v.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; _mainView=v;
    v.titleLabel=WLLabel(@"划词译",23,YES); v.subtitle=WLLabel(@"自动识别语言   →   简体中文",12,NO); v.subtitle.textColor=NSColor.secondaryLabelColor;
    v.settingsButton=WLButton(@"设置",self,@selector(openSettings:));
    v.clipboard=WLButton(@"翻译剪贴板",self,@selector(translateClipboard:));
    v.sourceLabel=WLLabel(@"原文",15,YES); v.resultLabel=WLLabel(@"中文译文",15,YES);
    v.counter=WLLabel(@"可编辑原文",11,NO); v.counter.textColor=NSColor.secondaryLabelColor;
    v.sourceCopyButton=WLButton(@"复制原文",self,@selector(copySource:)); v.resultCopyButton=WLButton(@"复制译文",self,@selector(copyResult:));
    v.translateButton=WLButton(@"翻译  ⌘↩",self,@selector(translate:)); v.translateButton.keyEquivalent=@"\r"; v.translateButton.keyEquivalentModifierMask=NSEventModifierFlagCommand;
    WLTextView *source=nil,*result=nil;
    v.sourceScroll=[self scrollForText:&source editable:YES placeholder:@"在其他应用中选中文字，再点击浮动「译」图标。\n\n也可以在这里输入或粘贴文本。"];
    v.resultScroll=[self scrollForText:&result editable:NO placeholder:@"中文译文会显示在这里。"];
    _sourceText=source; _sourceText.delegate=self; _resultText=result;
    v.spinner=[[NSProgressIndicator alloc] initWithFrame:NSZeroRect]; v.spinner.style=NSProgressIndicatorStyleSpinning; v.spinner.controlSize=NSControlSizeSmall; v.spinner.displayedWhenStopped=NO;
    v.status=WLLabel(@"准备就绪",12,NO); v.status.maximumNumberOfLines=2; v.status.lineBreakMode=NSLineBreakByTruncatingTail;
    v.cancelButton=WLButton(@"取消",self,@selector(cancelTranslation:)); v.cancelButton.hidden=YES;
    v.footer=WLLabel(@"选中文字 → 点击「译」    ·    快捷键 ⌥⌘T    ·    AI 翻译",11,NO); v.footer.textColor=NSColor.tertiaryLabelColor;
    for (NSView *view in @[v.titleLabel,v.subtitle,v.settingsButton,v.clipboard,v.sourceLabel,v.resultLabel,v.counter,v.sourceCopyButton,v.resultCopyButton,v.translateButton,v.sourceScroll,v.resultScroll,v.spinner,v.status,v.cancelButton,v.footer]) [v addSubview:view];
    _mainWindow.contentView=v; [v setNeedsLayout:YES]; [v layoutSubtreeIfNeeded]; [self refreshCopyButtons];
}
- (void)setStatus:(NSString *)status error:(BOOL)error { _mainView.status.stringValue=status ?: @""; _mainView.status.textColor=error ? NSColor.systemRedColor : NSColor.secondaryLabelColor; _mainView.status.toolTip=status; }
- (void)openMain:(id)sender { [_mainWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)loadText:(NSString *)text {
    [self cancelTranslation:nil]; _sourceText.string=text ?: @""; _resultText.string=@""; [_sourceText.undoManager removeAllActions];
    [_sourceText setSelectedRange:NSMakeRange(0,0)]; [_sourceText scrollRangeToVisible:NSMakeRange(0,0)];
    [_sourceText setNeedsDisplay:YES]; [_resultText setNeedsDisplay:YES]; [self updateCounter]; [self refreshCopyButtons]; [self openMain:nil];
    if (text.length>WLMaximumTextLength) [self setStatus:@"文本较长，请分成小于 24,000 个 UTF-16 单元的段落翻译。" error:YES];
    else if ([_settings.values[@"autoTranslate"] boolValue]) [self translate:nil];
    else [self setStatus:@"自动翻译已关闭，点击「翻译」开始。" error:NO];
}
- (void)updateCounter { _mainView.counter.stringValue=[NSString stringWithFormat:@"%lu 字符 · 可编辑",(unsigned long)_sourceText.string.length]; }
- (void)refreshCopyButtons { _mainView.sourceCopyButton.enabled=_sourceText.string.length>0; _mainView.resultCopyButton.enabled=_resultText.string.length>0; }
- (void)textDidChange:(NSNotification *)notification {
    if (notification.object!=_sourceText) return;
    [self cancelTranslation:nil]; _resultText.string=@""; [_resultText setNeedsDisplay:YES]; [self updateCounter]; [self refreshCopyButtons];
    [self setStatus:@"原文已更新，点击「翻译」或按 ⌘↩。" error:NO];
}
- (void)setBusy:(BOOL)busy { _mainView.translateButton.enabled=!busy; _mainView.cancelButton.hidden=!busy; busy ? [_mainView.spinner startAnimation:nil] : [_mainView.spinner stopAnimation:nil]; }
- (void)cancelTranslation:(id)sender { _translationGeneration++; [_translationTask cancel]; _translationTask=nil; [self setBusy:NO]; if (sender) [self setStatus:@"已取消翻译。" error:NO]; }
- (void)translate:(id)sender {
    [self cancelTranslation:nil];
    NSError *error=nil; NSDictionary *values=_settings.values;
    // Validate before reading Keychain so an unconfigured app never prompts for a key.
    if (!WLEndpoint(values[@"baseURL"],&error) || !WLTrim(values[@"model"]).length || !WLTrim(_sourceText.string).length) {
        [self setStatus:error.localizedDescription ?: (!WLTrim(_sourceText.string).length ? @"请先输入需要翻译的文本。" : @"请点击「设置」，填写模型名称和 API Key。") error:YES]; return;
    }
    NSString *key=[_settings keyForBase:values[@"baseURL"] error:&error];
    if (error) { [self setStatus:error.localizedDescription error:YES]; return; }
    if (!WLRequest(values,key,_sourceText.string,&error)) { [self setStatus:error.localizedDescription error:YES]; return; }
    _resultText.string=@""; [_resultText setNeedsDisplay:YES]; [self refreshCopyButtons]; [self setBusy:YES];
    [self setStatus:[NSString stringWithFormat:@"正在翻译 · %@",values[@"model"]] error:NO];
    NSUInteger generation=_translationGeneration; NSString *source=[_sourceText.string copy];
    __weak WLAppDelegate *weakSelf=self;
    _translationTask=[_client translate:source settings:values key:key completion:^(NSString *result,NSError *failure) {
        WLAppDelegate *app=weakSelf; if (!app || app.translationGeneration!=generation || ![app.sourceText.string isEqual:source]) return;
        app.translationTask=nil; [app setBusy:NO];
        if (failure) { if (failure.code!=NSURLErrorCancelled) [app setStatus:failure.localizedDescription error:YES]; }
        else { app.resultText.string=result; [app.resultText setNeedsDisplay:YES]; [app.resultText scrollRangeToVisible:NSMakeRange(0,0)]; [app setStatus:@"翻译完成" error:NO]; }
        [app refreshCopyButtons];
    }];
}
- (void)copyString:(NSString *)text name:(NSString *)name { if (!text.length) return; [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString]; [self setStatus:[NSString stringWithFormat:@"%@已复制",name] error:NO]; }
- (void)copySource:(id)sender { [self copyString:_sourceText.string name:@"原文"]; }
- (void)copyResult:(id)sender { [self copyString:_resultText.string name:@"译文"]; }
- (void)translateClipboard:(id)sender {
    NSString *text=[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (!WLTrim(text).length) { [self openMain:nil]; [self setStatus:@"剪贴板没有文本，请先复制需要翻译的内容。" error:YES]; return; }
    [self hideBubble]; [self loadText:text];
}
- (void)buildBubble {
    _bubble=[[WLBubble alloc] initWithContentRect:NSMakeRect(0,0,44,44) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _bubble.opaque=NO; _bubble.backgroundColor=NSColor.clearColor; _bubble.hasShadow=YES; _bubble.level=NSFloatingWindowLevel;
    _bubble.hidesOnDeactivate=NO; _bubble.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSButton *b=[NSButton buttonWithImage:WLLogo(44,NO) target:self action:@selector(bubbleClicked:)]; b.bordered=NO; b.frame=NSMakeRect(0,0,44,44); b.toolTip=@"翻译所选文字"; b.accessibilityLabel=@"翻译所选文字"; _bubble.contentView=b;
}
- (void)hideBubble { _selectionGeneration++; [_bubble orderOut:nil]; [_bubbleTimer invalidate]; _bubbleTimer=nil; _pendingSelection=nil; _pendingPID=0; }
- (void)showBubbleForText:(NSString *)text PID:(pid_t)pid point:(NSPoint)point {
    _pendingSelection=[text copy]; _pendingPID=pid;
    [(NSButton *)_bubble.contentView setToolTip:text.length ? @"翻译所选文字" : @"兼容模式：点击后复制所选文字并翻译"];
    NSScreen *screen=NSScreen.mainScreen; for (NSScreen *s in NSScreen.screens) if (NSPointInRect(point,s.frame)) { screen=s; break; }
    [_bubble setFrame:WLClampedBubbleFrame(point,screen.visibleFrame) display:NO]; [_bubble orderFrontRegardless];
    [_bubbleTimer invalidate]; _bubbleTimer=[NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(bubbleExpired:) userInfo:nil repeats:NO];
}
- (void)bubbleExpired:(NSTimer *)timer { [self hideBubble]; }
- (void)bubbleClicked:(id)sender {
    NSString *text=[_pendingSelection copy]; pid_t pid=_pendingPID; [self hideBubble];
    if (text.length) [self loadText:text]; else [self copySelectionForPID:pid generation:_selectionGeneration];
}
- (void)selectionReadFailed:(NSString *)message { [self openMain:nil]; [self setStatus:message error:YES]; }
- (void)copySelectionForPID:(pid_t)pid generation:(NSUInteger)generation {
    if (![_settings.values[@"copyFallback"] boolValue]) { [self selectionReadFailed:@"此应用无法直接读取所选文本。可在设置中开启 PDF / 复制兼容模式，或手动复制后点击「翻译剪贴板」。"]; return; }
    if (!AXIsProcessTrusted()) { [self selectionReadFailed:@"请在设置中开启辅助功能；也可复制后点击「翻译剪贴板」。"]; return; }
    if ([WLSelection focusedFieldIsSecureForPID:pid]) { [self selectionReadFailed:@"不读取密码输入框的内容。"]; return; }
    __weak WLAppDelegate *weakSelf=self;
    [_selectionCopier captureForPID:pid completion:^(NSString *text,NSError *error) {
        WLAppDelegate *app=weakSelf; if (!app || app.selectionGeneration!=generation) return;
        if (text.length) [app loadText:text];
        else if (error.code!=NSURLErrorCancelled) [app selectionReadFailed:error.localizedDescription];
    }];
}
- (void)frontAppChanged:(NSNotification *)notification { [self hideBubble]; [_selectionCopier cancel]; _mouseDownPID=0; }
- (void)installMonitors {
    __weak WLAppDelegate *weakSelf=self;
    _mouseMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskLeftMouseUp|NSEventMaskLeftMouseDragged handler:^(NSEvent *event) {
        WLAppDelegate *app=weakSelf;
        if (event.type==NSEventTypeLeftMouseDown) {
            [app hideBubble]; [app.selectionCopier cancel]; app.mouseDownPID=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
            app.mouseDownPoint=NSEvent.mouseLocation; app.mouseDragged=NO;
        } else if (event.type==NSEventTypeLeftMouseDragged) { app.mouseDragged=YES; if (!app.mouseDownPID) app.mouseDownPID=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier; }
        else {
            BOOL same=app.mouseDownPID>0 && app.mouseDownPID==NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
            BOOL gesture=WLIsSelectionGesture(app.mouseDownPoint,NSEvent.mouseLocation,event.clickCount,app.mouseDragged,same);
            gesture=gesture && !(event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagControl));
            app.mouseDownPID=0; [app scheduleSelectionWithCopyFallback:gesture];
        }
    }];
    _keyMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown|NSEventMaskKeyUp handler:^(NSEvent *event) {
        WLAppDelegate *app=weakSelf;
        if (event.CGEvent && CGEventGetIntegerValueField(event.CGEvent,kCGEventSourceUserData)==WLCopyEventTag) return;
        BOOL shortcut=event.keyCode==kVK_ANSI_T && (event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagOption))==(NSEventModifierFlagCommand|NSEventModifierFlagOption);
        if (shortcut || (event.type==NSEventTypeKeyUp && event.keyCode==kVK_ANSI_T && app.shortcutKeyReleaseExpected)) { if (event.type==NSEventTypeKeyUp) app.shortcutKeyReleaseExpected=NO; return; }
        if (event.type==NSEventTypeKeyDown) { [app hideBubble]; [app.selectionCopier cancel]; return; }
        if (event.keyCode==kVK_Escape) [app hideBubble];
        else if ((event.modifierFlags & NSEventModifierFlagShift) || (event.keyCode==kVK_ANSI_A && (event.modifierFlags & NSEventModifierFlagCommand))) [app scheduleSelectionWithCopyFallback:NO];
        else [app hideBubble];
    }];
    _localMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown|NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
        [weakSelf.selectionCopier cancel];
        if (event.type==NSEventTypeKeyDown && event.keyCode==kVK_Escape) { [weakSelf hideBubble]; if (weakSelf.translationTask) [weakSelf cancelTranslation:event]; }
        return event;
    }];
}
- (void)scheduleSelectionWithCopyFallback:(BOOL)allowCopy {
    if (![_settings.values[@"monitorSelection"] boolValue] || !AXIsProcessTrusted()) return;
    NSRunningApplication *front=NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!front || front.processIdentifier==getpid()) return;
    NSUInteger generation=++_selectionGeneration; pid_t pid=front.processIdentifier; NSPoint point=NSEvent.mouseLocation;
    [self probeSelectionForPID:pid point:point generation:generation allowCopy:allowCopy openWindow:NO attempt:0];
}
- (void)probeSelectionForPID:(pid_t)pid point:(NSPoint)point generation:(NSUInteger)generation allowCopy:(BOOL)allowCopy openWindow:(BOOL)openWindow attempt:(NSUInteger)attempt {
    __weak WLAppDelegate *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((attempt==0 ? .16 : .28)*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        WLAppDelegate *app=weakSelf; if (!app || app.selectionGeneration!=generation) return;
        if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
        dispatch_async(app.selectionQueue, ^{
            if (app.selectionGeneration!=generation) return;
            NSString *text=[WLSelection selectedTextForPID:pid atPoint:point];
            if (app.selectionGeneration!=generation) return;
            BOOL secure=[WLSelection focusedFieldIsSecureForPID:pid];
            dispatch_async(dispatch_get_main_queue(), ^{
                WLAppDelegate *owner=weakSelf;
                if (!owner || generation!=owner.selectionGeneration || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
                if (WLTrim(text).length) {
                    if (openWindow) [owner loadText:text]; else [owner showBubbleForText:text PID:pid point:point];
                } else if (attempt==0 && !secure) [owner probeSelectionForPID:pid point:point generation:generation allowCopy:allowCopy openWindow:openWindow attempt:1];
                else if (openWindow) {
                    if (!secure) [owner copySelectionForPID:pid generation:generation];
                    else [owner selectionReadFailed:@"不读取密码输入框的内容。"]; 
                } else if (allowCopy && !secure && [owner.settings.values[@"copyFallback"] boolValue]) [owner showBubbleForText:nil PID:pid point:point];
                else [owner hideBubble];
            });
        });
    });
}
- (void)translateSelectionShortcut:(id)sender {
    NSRunningApplication *front=NSWorkspace.sharedWorkspace.frontmostApplication;
    if (front.processIdentifier==getpid()) { [self translate:sender]; return; }
    _shortcutKeyReleaseExpected=YES;
    if (!AXIsProcessTrusted()) { [self selectionReadFailed:@"请在设置中开启辅助功能；也可复制后点击「翻译剪贴板」。"]; return; }
    pid_t pid=front.processIdentifier; NSPoint point=NSEvent.mouseLocation;
    [self hideBubble]; [_selectionCopier cancel];
    [self probeSelectionForPID:pid point:point generation:_selectionGeneration allowCopy:YES openWindow:YES attempt:0];
}
- (void)refreshPauseMenu { _pauseItem.state=[_settings.values[@"monitorSelection"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff; }
- (void)toggleMonitor:(id)sender {
    NSMutableDictionary *values=[_settings.values mutableCopy]; values[@"monitorSelection"]=@(![values[@"monitorSelection"] boolValue]); [_settings saveValues:values]; [self refreshPauseMenu]; [self hideBubble]; [_selectionCopier cancel];
    _monitorCheckbox.state=[values[@"monitorSelection"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (NSTextField *)settingsField:(NSString *)placeholder frame:(NSRect)frame secure:(BOOL)secure {
    NSTextField *field=secure ? [[NSSecureTextField alloc] initWithFrame:frame] : [[NSTextField alloc] initWithFrame:frame];
    field.placeholderString=placeholder; field.font=[NSFont systemFontOfSize:14]; field.bezelStyle=NSTextFieldRoundedBezel;
    field.usesSingleLineMode=YES; field.lineBreakMode=NSLineBreakByTruncatingMiddle; return field;
}
- (void)buildSettingsWindow {
    _settingsWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,570,694) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    _settingsWindow.title=@"划词译 · 设置"; _settingsWindow.releasedWhenClosed=NO; _settingsWindow.delegate=self; [_settingsWindow center];
    WLFlippedView *v=[[WLFlippedView alloc] initWithFrame:NSMakeRect(0,0,570,694)]; _settingsWindow.contentView=v;
    NSTextField *title=WLLabel(@"连接你的 AI 模型",22,YES); title.frame=NSMakeRect(26,18,518,30); [v addSubview:title];
    NSTextField *desc=WLLabel(@"支持 OpenAI 兼容的 Chat Completions 接口",12,NO); desc.textColor=NSColor.secondaryLabelColor; desc.frame=NSMakeRect(26,54,518,22); [v addSubview:desc];
    NSArray *labels=@[@"AI Base URL",@"模型名称",@"API Key"];
    for (int i=0;i<3;i++) { NSTextField *label=WLLabel(labels[i],13,YES); label.frame=NSMakeRect(26,94+i*82,518,20); [v addSubview:label]; }
    _baseField=[self settingsField:@"https://api.openai.com/v1" frame:NSMakeRect(26,119,518,30) secure:NO]; _baseField.delegate=self;
    _modelField=[self settingsField:@"填写服务商提供的模型 ID" frame:NSMakeRect(26,201,518,30) secure:NO];
    _keyField=(NSSecureTextField *)[self settingsField:@"保存在 macOS 钥匙串 · 本机服务可留空" frame:NSMakeRect(26,283,518,30) secure:YES];
    _modelField.delegate=self; _keyField.delegate=self;
    _baseField.accessibilityLabel=@"AI Base URL"; _modelField.accessibilityLabel=@"模型名称"; _keyField.accessibilityLabel=@"API Key";
    [v addSubview:_baseField]; [v addSubview:_modelField]; [v addSubview:_keyField];
    NSTextField *keyHint=WLLabel(@"密钥按接口地址分别保存；清空后保存可删除该接口的密钥。",11,NO); keyHint.textColor=NSColor.secondaryLabelColor; keyHint.frame=NSMakeRect(26,322,518,22); [v addSubview:keyHint];
    _autoCheckbox=[NSButton checkboxWithTitle:@"打开所选文本后自动翻译" target:nil action:nil]; _autoCheckbox.frame=NSMakeRect(26,359,270,24); [v addSubview:_autoCheckbox];
    _monitorCheckbox=[NSButton checkboxWithTitle:@"选中文字后显示浮动图标" target:nil action:nil]; _monitorCheckbox.frame=NSMakeRect(26,393,270,24); [v addSubview:_monitorCheckbox];
    _fallbackCheckbox=[NSButton checkboxWithTitle:@"PDF / 复制兼容模式" target:nil action:nil]; _fallbackCheckbox.frame=NSMakeRect(26,427,518,24); [v addSubview:_fallbackCheckbox];
    NSTextField *fallbackHint=WLLabel(@"直接读取失败时，点击图标后复制选区并尽量还原剪贴板。\n拖选或双击后可显示备用图标；关闭此项可禁用备用方式。",11,NO); fallbackHint.maximumNumberOfLines=2; fallbackHint.textColor=NSColor.secondaryLabelColor; fallbackHint.frame=NSMakeRect(26,457,518,36); [v addSubview:fallbackHint];
    NSTextField *timeout=WLLabel(@"请求超时（秒）",12,NO); timeout.frame=NSMakeRect(332,362,135,20); [v addSubview:timeout];
    _timeoutField=[self settingsField:@"60" frame:NSMakeRect(474,358,70,28) secure:NO]; _timeoutField.delegate=self; _timeoutField.accessibilityLabel=@"请求超时秒数"; [v addSubview:_timeoutField];
    NSTextField *timeoutHint=WLLabel(@"10–180 秒",11,NO); timeoutHint.frame=NSMakeRect(474,393,74,20); timeoutHint.textColor=NSColor.secondaryLabelColor; [v addSubview:timeoutHint];
    _permissionLabel=WLLabel(@"辅助功能：尚未授权",12,YES); _permissionLabel.frame=NSMakeRect(26,504,340,23); [v addSubview:_permissionLabel];
    NSButton *permission=WLButton(@"开启辅助功能",self,@selector(openAccessibility:)); permission.frame=NSMakeRect(405,498,139,32); [v addSubview:permission];
    NSTextField *privacy=WLLabel(@"点击「译」或翻译按钮时，原文才会发送至所设接口。\n应用不保存翻译历史；关闭窗口会清除原文和译文。",11,NO); privacy.maximumNumberOfLines=2; privacy.textColor=NSColor.secondaryLabelColor; privacy.frame=NSMakeRect(26,542,518,40); [v addSubview:privacy];
    _settingsStatus=WLLabel(@"填写参数后，可先测试连接。",12,NO); _settingsStatus.maximumNumberOfLines=2; _settingsStatus.frame=NSMakeRect(26,592,518,40); _settingsStatus.textColor=NSColor.secondaryLabelColor; [v addSubview:_settingsStatus];
    _testButton=WLButton(@"测试连接",self,@selector(testConnection:)); _testButton.frame=NSMakeRect(26,645,107,32); [v addSubview:_testButton];
    NSButton *cancel=WLButton(@"取消",self,@selector(closeSettings:)); cancel.frame=NSMakeRect(350,645,84,32); [v addSubview:cancel];
    NSButton *save=WLButton(@"保存设置",self,@selector(saveSettings:)); save.frame=NSMakeRect(441,645,103,32); save.keyEquivalent=@"\r"; [v addSubview:save];
}
- (void)openSettings:(id)sender {
    if (!_settingsWindow) [self buildSettingsWindow];
    if (!_settingsWindow.visible) {
        [self stopConnectionTest]; NSDictionary *values=_settings.values;
        _baseField.stringValue=values[@"baseURL"]; _modelField.stringValue=values[@"model"]; _timeoutField.stringValue=[values[@"timeout"] stringValue];
        _autoCheckbox.state=[values[@"autoTranslate"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        _monitorCheckbox.state=[values[@"monitorSelection"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        _fallbackCheckbox.state=[values[@"copyFallback"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        _loadedKeyEndpoint=nil; [self loadKeyForDraftBase];
        if (!_baseKeyLoadFailed) { _settingsStatus.stringValue=@"填写参数后，可先测试连接。"; _settingsStatus.textColor=NSColor.secondaryLabelColor; }
    }
    [self refreshPermission]; [_permissionTimer invalidate]; _permissionTimer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(permissionTick:) userInfo:nil repeats:YES];
    [_settingsWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)refreshPermission { _permissionLabel.stringValue=AXIsProcessTrusted() ? @"辅助功能：已授权 ✓" : @"辅助功能：尚未授权"; _permissionLabel.textColor=AXIsProcessTrusted() ? NSColor.systemGreenColor : NSColor.secondaryLabelColor; }
- (void)permissionTick:(NSTimer *)timer { if (!_settingsWindow.visible) { [timer invalidate]; _permissionTimer=nil; } else [self refreshPermission]; }
- (void)openAccessibility:(id)sender {
    NSDictionary *options=@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES}; AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (void)loadKeyForDraftBase {
    if (_previewMode) return;
    NSString *endpoint=WLEndpoint(_baseField.stringValue,nil).absoluteString ?: WLTrim(_baseField.stringValue);
    if ([_loadedKeyEndpoint isEqual:endpoint]) return;
    _loadedKeyEndpoint=endpoint;
    NSError *error=nil; NSString *key=[_settings keyForBase:_baseField.stringValue error:&error]; _baseKeyLoadFailed=error!=nil;
    _keyField.stringValue=key ?: @"";
    if (error) { _settingsStatus.stringValue=error.localizedDescription; _settingsStatus.textColor=NSColor.systemRedColor; }
}
- (void)controlTextDidEndEditing:(NSNotification *)notification { if (notification.object==_baseField) [self loadKeyForDraftBase]; }
- (void)controlTextDidChange:(NSNotification *)notification { [self stopConnectionTest]; _settingsStatus.stringValue=@"参数已更新，可重新测试。"; _settingsStatus.textColor=NSColor.secondaryLabelColor; }
- (NSDictionary *)draftValues:(NSError **)error {
    NSMutableDictionary *values=[_settings.values mutableCopy]; values[@"baseURL"]=WLTrim(_baseField.stringValue); values[@"model"]=WLTrim(_modelField.stringValue);
    NSScanner *scan=[NSScanner scannerWithString:WLTrim(_timeoutField.stringValue)]; NSInteger seconds=0;
    if (![scan scanInteger:&seconds] || !scan.isAtEnd || seconds<10 || seconds>180) { if (error) *error=WLError(@"超时时间请填写 10–180 之间的整数。 "); return nil; }
    values[@"timeout"]=@(seconds); values[@"autoTranslate"]=@(_autoCheckbox.state==NSControlStateValueOn); values[@"monitorSelection"]=@(_monitorCheckbox.state==NSControlStateValueOn); values[@"copyFallback"]=@(_fallbackCheckbox.state==NSControlStateValueOn);
    if (!WLEndpoint(values[@"baseURL"],error)) return nil;
    if (![values[@"model"] length]) { if (error) *error=WLError(@"请填写模型名称。"); return nil; }
    return values;
}
- (void)saveSettings:(id)sender {
    [_settingsWindow makeFirstResponder:nil];
    NSError *error=nil; NSDictionary *values=[self draftValues:&error];
    if (_baseKeyLoadFailed && !_keyField.stringValue.length) error=WLError(@"钥匙串读取失败，请解锁钥匙串或重新填写 API Key 后保存。");
    if (!error && ![_settings saveKey:WLTrim(_keyField.stringValue) base:values[@"baseURL"] error:&error]) values=nil;
    if (error || !values) { _settingsStatus.stringValue=error.localizedDescription; _settingsStatus.textColor=NSColor.systemRedColor; return; }
    [self cancelTranslation:nil]; [_settings saveValues:values]; [self refreshPauseMenu]; [self hideBubble]; [_selectionCopier cancel];
    [self closeSettings:nil]; [self setStatus:@"设置已保存，点击「翻译」开始。" error:NO];
}
- (void)stopConnectionTest { _testGeneration++; [_testTask cancel]; _testTask=nil; _testButton.enabled=YES; _testButton.title=@"测试连接"; }
- (void)testConnection:(id)sender {
    [_settingsWindow makeFirstResponder:nil]; [self stopConnectionTest];
    NSError *error=nil; NSDictionary *values=[self draftValues:&error]; NSString *key=WLTrim(_keyField.stringValue);
    if (values && !WLRequest(values,key,@"Hello, world!",&error)) values=nil;
    if (error || !values) { _settingsStatus.stringValue=error.localizedDescription; _settingsStatus.textColor=NSColor.systemRedColor; return; }
    _testButton.enabled=NO; _testButton.title=@"测试中…"; _settingsStatus.stringValue=@"正在发送一条简短的翻译测试请求…"; _settingsStatus.textColor=NSColor.secondaryLabelColor;
    NSUInteger generation=_testGeneration; __weak WLAppDelegate *weakSelf=self;
    _testTask=[_client translate:@"Hello, world!" settings:values key:key completion:^(NSString *result,NSError *failure) {
        WLAppDelegate *app=weakSelf; if (!app || app.testGeneration!=generation) return;
        app.testTask=nil; app.testButton.enabled=YES; app.testButton.title=@"测试连接";
        app.settingsStatus.stringValue=failure ? failure.localizedDescription : [@"连接成功 · " stringByAppendingString:result];
        app.settingsStatus.textColor=failure ? NSColor.systemRedColor : NSColor.systemGreenColor;
    }];
}
- (void)closeSettings:(id)sender { [self stopConnectionTest]; [_permissionTimer invalidate]; _permissionTimer=nil; _keyField.stringValue=@""; [_settingsWindow orderOut:nil]; }
- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object==_settingsWindow) [self closeSettings:nil];
    else if (notification.object==_mainWindow) {
        [self cancelTranslation:nil]; _sourceText.string=@""; _resultText.string=@""; [_sourceText.undoManager removeAllActions]; [self updateCounter]; [self refreshCopyButtons]; [self setStatus:@"准备就绪" error:NO];
    }
}
- (void)renderPreview:(NSString *)path settings:(BOOL)settingsPreview {
    _previewMode=YES; _settings=[WLSettings new]; [self buildMainWindow];
    _sourceText.string=@"Finally, we note that this calibration incurs a small computational and memory overhead. Combined with rectification, it helps accumulate new knowledge from emerging classes in open-world object detection.";
    _resultText.string=@"最后，我们指出，这种校准只会带来少量的计算和内存开销。结合校正方法，它有助于在开放世界目标检测中，不断积累来自新出现类别的知识。";
    [self updateCounter]; [self refreshCopyButtons]; [self setStatus:@"翻译完成 · 界面示例（非实时模型结果）" error:NO];
    NSWindow *window=_mainWindow;
    if (settingsPreview) {
        [self buildSettingsWindow]; _baseField.stringValue=WLDefaultBaseURL; _modelField.stringValue=@"your-model-id"; _keyField.stringValue=@"preview-placeholder-key"; _timeoutField.stringValue=@"60";
        _autoCheckbox.state=NSControlStateValueOn; _monitorCheckbox.state=NSControlStateValueOn; _fallbackCheckbox.state=NSControlStateValueOn; _permissionLabel.stringValue=@"辅助功能：在系统设置中授权"; window=_settingsWindow;
    }
    [window orderFront:nil]; [window.contentView layoutSubtreeIfNeeded]; [window display];
    NSBitmapImageRep *rep=[window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
    [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]; [window orderOut:nil];
}
@end
