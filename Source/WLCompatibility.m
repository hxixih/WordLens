#import "WLCompatibility.h"
#import "WLCore.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

const int64_t WLCopyEventTag = 0x574c436f7079;
BOOL WLIsSelectionGesture(NSPoint start, NSPoint end, NSInteger clickCount, BOOL dragged, BOOL sameApplication) {
    return sameApplication && (clickCount>=2 || (dragged && hypot(end.x-start.x,end.y-start.y)>=6));
}
NSString *WLSubstringForSelection(NSString *value, CFRange range) {
    if (![value isKindOfClass:NSString.class] || range.location<0 || range.length<=0 || (NSUInteger)range.location>value.length || (NSUInteger)range.length>value.length-(NSUInteger)range.location) return nil;
    return [value substringWithRange:NSMakeRange((NSUInteger)range.location,(NSUInteger)range.length)];
}
BOOL WLSendCopyToPID(pid_t pid) {
    if (pid<=0 || pid==getpid() || !AXIsProcessTrusted() || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return NO;
    CGEventRef down=CGEventCreateKeyboardEvent(NULL,kVK_ANSI_C,true);
    CGEventRef up=CGEventCreateKeyboardEvent(NULL,kVK_ANSI_C,false);
    if (!down || !up) { if (down) CFRelease(down); if (up) CFRelease(up); return NO; }
    CGEventSetFlags(down,kCGEventFlagMaskCommand); CGEventSetFlags(up,kCGEventFlagMaskCommand);
    CGEventSetIntegerValueField(down,kCGEventSourceUserData,WLCopyEventTag); CGEventSetIntegerValueField(up,kCGEventSourceUserData,WLCopyEventTag);
    // Deliver only to the original application, never to a newly focused window.
    CGEventPostToPid(pid,down); CGEventPostToPid(pid,up); CFRelease(down); CFRelease(up); return YES;
}

@interface WLPasteboard ()
@property(nonatomic,strong) NSPasteboard *pasteboard;
@end
@implementation WLPasteboard
- (instancetype)initWithPasteboard:(NSPasteboard *)pasteboard { if ((self=[super init])) _pasteboard=pasteboard; return self; }
- (NSInteger)changeCount { return _pasteboard.changeCount; }
- (NSString *)text { return [_pasteboard stringForType:NSPasteboardTypeString]; }
- (NSArray *)snapshot:(NSError **)error {
    NSInteger before=_pasteboard.changeCount; NSUInteger bytes=0; NSMutableArray *items=[NSMutableArray array];
    for (NSPasteboardItem *item in _pasteboard.pasteboardItems) {
        NSMutableDictionary *representations=[NSMutableDictionary dictionary];
        for (NSString *type in item.types) {
            NSData *data=[item dataForType:type];
            if (!data || data.length>16*1024*1024-bytes) {
                if (error) *error=WLError(@"当前剪贴板内容无法完整备份，请手动复制 PDF 文字，再使用「翻译剪贴板」。"); return nil;
            }
            bytes+=data.length; representations[type]=data;
        }
        [items addObject:representations];
    }
    if (_pasteboard.changeCount!=before) { if (error) *error=WLError(@"剪贴板正在变化，请稍后再点击「译」。"); return nil; }
    return items;
}
- (BOOL)restore:(NSArray *)snapshot ifUnchanged:(NSInteger)count {
    NSMutableArray *items=[NSMutableArray array];
    for (NSDictionary *representations in snapshot) {
        NSPasteboardItem *item=[NSPasteboardItem new];
        for (NSString *type in representations) if (![item setData:representations[type] forType:type]) return NO;
        [items addObject:item];
    }
    if (_pasteboard.changeCount!=count) return NO;
    [_pasteboard clearContents]; return !items.count || [_pasteboard writeObjects:items];
}
@end

@interface WLCopyCapture ()
@property(nonatomic) BOOL running;
@property(nonatomic,strong) id<WLClipboard> clipboard;
@property(nonatomic,copy) pid_t (^frontPID)(void);
@property(nonatomic,copy) BOOL (^sendCopy)(pid_t);
@property(nonatomic,copy) void (^completion)(NSString *, NSError *);
@property(nonatomic,strong) NSArray *savedClipboard;
@property(nonatomic) NSInteger initialCount;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) pid_t sourcePID;
@property(nonatomic) CFAbsoluteTime deadline;
@end
@implementation WLCopyCapture
- (instancetype)initWithClipboard:(id<WLClipboard>)clipboard frontPID:(pid_t (^)(void))frontPID sendCopy:(BOOL (^)(pid_t))sendCopy {
    if ((self=[super init])) { _clipboard=clipboard; _frontPID=[frontPID copy]; _sendCopy=[sendCopy copy]; } return self;
}
- (void)finish:(NSString *)text error:(NSError *)error {
    void (^callback)(NSString *,NSError *)=_completion;
    _running=NO; _completion=nil; _savedClipboard=nil;
    if (callback) callback(text,error);
}
- (void)cancel {
    _generation++;
    if (_running) [self finish:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
}
- (void)captureForPID:(pid_t)pid completion:(void (^)(NSString *, NSError *))completion {
    NSAssert(NSThread.isMainThread,@"Copy capture must run on the main thread");
    if (_running) { completion(nil,WLError(@"正在读取选区，请稍候。")); return; }
    if (pid<=0 || _frontPID()!=pid) { completion(nil,WLError(@"原应用已切换，请重新选中文字。")); return; }
    NSError *error=nil; NSInteger initial=_clipboard.changeCount;
    NSArray *snapshot=[_clipboard snapshot:&error];
    if (!snapshot || _clipboard.changeCount!=initial || _frontPID()!=pid) { completion(nil,error ?: WLError(@"剪贴板或原应用已变化，请重新选中文字。")); return; }
    _running=YES; _sourcePID=pid; _initialCount=initial; _savedClipboard=snapshot; _completion=[completion copy]; _deadline=CFAbsoluteTimeGetCurrent()+.9; NSUInteger generation=++_generation;
    if (!_sendCopy(pid)) { [self finish:nil error:WLError(@"无法执行选区复制，请检查辅助功能授权，或手动复制后使用「翻译剪贴板」。")]; return; }
    [self schedulePoll:generation];
}
- (void)schedulePoll:(NSUInteger)generation {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.045*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        if (!self.running || self.generation!=generation) return;
        if (self.frontPID()!=self.sourcePID) { [self finish:nil error:WLError(@"原应用已切换，选区读取已取消。")]; return; }
        NSInteger count=self.clipboard.changeCount;
        if (count!=self.initialCount) {
            NSString *text=[self.clipboard.text copy];
            // The copy must produce a new clipboard value; never translate an old one.
            if (self.clipboard.changeCount!=count || self.frontPID()!=self.sourcePID) { [self finish:nil error:WLError(@"剪贴板在读取期间变化，请重新选中文字。")]; return; }
            BOOL restored=[self.clipboard restore:self.savedClipboard ifUnchanged:count];
            if (!restored) { [self finish:nil error:WLError(@"剪贴板未能还原，已取消读取。请手动复制后使用「翻译剪贴板」。")]; return; }
            [self finish:WLTrim(text).length ? text : nil error:WLTrim(text).length ? nil : WLError(@"未复制到选中的文字，请确认 PDF 允许文本复制，或手动复制后使用「翻译剪贴板」。")];
        } else if (CFAbsoluteTimeGetCurrent()>=self.deadline) [self finish:nil error:WLError(@"未能复制所选文字，请手动复制后使用「翻译剪贴板」。")];
        else [self schedulePoll:generation];
    });
}
@end
