#import "../Source/WLCompatibility.h"
#import "../Source/WLCore.h"

static int total=0,failed=0;
static void Check(BOOL value,NSString *name) { total++; if (!value) { failed++; fprintf(stderr,"FAIL: %s\n",name.UTF8String); } }
static BOOL Pump(BOOL (^done)(void)) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && deadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return done();
}
static void After(NSTimeInterval delay,void (^block)(void)) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),block); }

@interface WLFakeClipboard : NSObject <WLClipboard>
@property(nonatomic) NSInteger changeCount;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,copy) NSString *textValue;
@property(nonatomic) BOOL snapshotFails,restoreFails,changeDuringRead;
@property(nonatomic) NSInteger restores,textReads;
@end
@implementation WLFakeClipboard
- (NSArray *)snapshot:(NSError **)error { if (_snapshotFails) { if (error) *error=WLError(@"snapshot failed"); return nil; } return _items; }
- (NSString *)text { _textReads++; if (_changeDuringRead) { _changeCount++; _textValue=@"new user clipboard"; } return _textValue; }
- (BOOL)restore:(NSArray *)snapshot ifUnchanged:(NSInteger)count { if (_restoreFails || _changeCount!=count) return NO; _items=snapshot; _restores++; _changeCount++; return YES; }
@end
static WLFakeClipboard *Board(void) {
    WLFakeClipboard *b=[WLFakeClipboard new]; b.changeCount=10; b.textValue=@"OLD TEXT MUST NOT BE TRANSLATED";
    b.items=@[@{@"public.utf8-plain-text":[@"old" dataUsingEncoding:NSUTF8StringEncoding],@"public.rtf":[@"{rtf}" dataUsingEncoding:NSUTF8StringEncoding]},@{@"public.png":[NSData dataWithBytes:"png" length:3]}]; return b;
}
static WLCopyCapture *Copier(WLFakeClipboard *b,pid_t (^pid)(void),BOOL (^send)(pid_t)) { return [[WLCopyCapture alloc] initWithClipboard:b frontPID:pid sendCopy:send]; }
int main(void) {
    @autoreleasepool {
        Check(WLIsSelectionGesture(NSMakePoint(0,0),NSMakePoint(30,0),1,YES,YES),@"same-app drag qualifies for compatibility icon");
        Check(WLIsSelectionGesture(NSZeroPoint,NSZeroPoint,2,NO,YES),@"double click qualifies");
        Check(!WLIsSelectionGesture(NSZeroPoint,NSMakePoint(1,0),1,YES,YES),@"small mouse jitter does not qualify");
        Check(!WLIsSelectionGesture(NSZeroPoint,NSMakePoint(30,0),1,NO,YES),@"mouse movement without dragging does not qualify");
        Check(!WLIsSelectionGesture(NSZeroPoint,NSMakePoint(30,0),1,YES,NO),@"cross-app drag does not qualify");
        Check([WLSubstringForSelection(@"before 中文 🌍 after",CFRangeMake(7,5)) isEqual:@"中文 🌍"],@"selected range supports Chinese and surrogate pairs");
        Check(!WLSubstringForSelection(@"abc",CFRangeMake(-1,1)),@"negative range rejected");
        Check(!WLSubstringForSelection(@"abc",CFRangeMake(0,0)),@"empty range rejected");
        Check(!WLSubstringForSelection(@"abc",CFRangeMake(2,2)),@"out-of-bounds range rejected");
        Check(!WLSubstringForSelection(@"abc",CFRangeMake(LONG_MAX,LONG_MAX)),@"overflowing range rejected");
        Check(!WLSubstringForSelection((id)@[],CFRangeMake(0,1)),@"non-string AX value rejected");

        // Success: multiple clipboard representations survive; only new text is returned.
        WLFakeClipboard *board=Board(); NSArray *original=board.items; __block NSInteger sent=0;
        WLCopyCapture *capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { sent++; Check(pid==123,@"copy targets original PID"); After(.08,^{ board.changeCount++; board.textValue=@"PDF selected text"; board.items=@[]; }); return YES; });
        __block BOOL done=NO; [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check([text isEqual:@"PDF selected text"] && !error,@"successful selection capture"); Check(NSThread.isMainThread,@"capture callback runs on main thread"); done=YES; }];
        Check(Pump(^BOOL { return done; }),@"selection capture completes"); Check(sent==1 && board.restores==1 && [board.items isEqual:original],@"all clipboard items and formats restored"); Check(!capture.running,@"capture finishes idle");

        // A blocked/unsupported Copy command must never return the old clipboard text.
        board=Board(); original=board.items; capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { return YES; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"copy timeout never returns stale clipboard"); done=YES; }];
        Check(Pump(^BOOL { return done; }),@"copy timeout completes"); Check(board.textReads==0 && board.restores==0 && [board.items isEqual:original],@"timeout leaves original clipboard untouched");

        // Image-only copied content is not translated, but old clipboard is restored.
        board=Board(); capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { board.changeCount++; board.textValue=nil; return YES; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"non-text copy rejected"); done=YES; }]; Check(Pump(^BOOL { return done; }) && board.restores==1,@"non-text copy still restores clipboard");

        // Switching application after Copy must not translate or overwrite a new user's value.
        board=Board(); __block pid_t front=123;
        capture=Copier(board,^pid_t { return front; },^BOOL(pid_t pid) { front=456; board.changeCount++; board.textValue=@"new user clipboard"; return YES; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"focus change cancels capture"); done=YES; }]; Check(Pump(^BOOL { return done; }) && board.restores==0 && [board.textValue isEqual:@"new user clipboard"],@"focus change preserves new clipboard");

        board=Board(); sent=0; capture=Copier(board,^pid_t { return 456; },^BOOL(pid_t pid) { sent++; return YES; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"wrong front application rejected before copy"); done=YES; }]; Check(done && sent==0,@"no synthetic copy sent to wrong app");

        board=Board(); board.snapshotFails=YES; sent=0; capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { sent++; return YES; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"failed clipboard backup rejects capture"); done=YES; }]; Check(done && sent==0,@"failed backup performs no copy");

        board=Board(); capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { return NO; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"failed key delivery rejected"); done=YES; }]; Check(done && !capture.running && board.restores==0,@"failed delivery leaves clipboard untouched");

        board=Board(); board.changeDuringRead=YES; capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { board.changeCount++; board.textValue=@"copied selection"; return YES; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"concurrent clipboard write rejects capture"); done=YES; }]; Check(Pump(^BOOL { return done; }) && board.restores==0 && [board.textValue isEqual:@"new user clipboard"],@"concurrent write is not overwritten");

        board=Board(); capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { return YES; }); done=NO; __block NSInteger callbacks=0;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { callbacks++; Check(!text && error.code==NSURLErrorCancelled,@"user activity cancellation propagates"); done=YES; }];
        [capture cancel]; Check(done && !capture.running,@"cancel completes immediately"); __block BOOL settled=NO; After(.12,^{ settled=YES; }); Check(Pump(^BOOL { return settled; }) && callbacks==1 && board.restores==0,@"delayed polls after cancel are ignored");

        board=Board(); board.restoreFails=YES; capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { board.changeCount++; board.textValue=@"copied selection"; return YES; }); done=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { Check(!text && error,@"restore failure is reported and capture discarded"); done=YES; }]; Check(Pump(^BOOL { return done; }),@"restore failure completes");

        board=Board(); capture=Copier(board,^pid_t { return 123; },^BOOL(pid_t pid) { return YES; }); __block BOOL secondRejected=NO;
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) {}];
        [capture captureForPID:123 completion:^(NSString *text,NSError *error) { secondRejected=!text && error!=nil; }]; Check(secondRejected,@"concurrent capture requests rejected"); [capture cancel];

        printf("%d compatibility checks, %d failures\n",total,failed); return failed ? 1 : 0;
    }
}
