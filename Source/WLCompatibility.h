#import <Cocoa/Cocoa.h>

extern const int64_t WLCopyEventTag;
BOOL WLIsSelectionGesture(NSPoint start, NSPoint end, NSInteger clickCount, BOOL dragged, BOOL sameApplication);
NSString *WLSubstringForSelection(NSString *value, CFRange range);
BOOL WLSendCopyToPID(pid_t pid);

@protocol WLClipboard <NSObject>
- (NSInteger)changeCount;
- (NSArray<NSDictionary<NSString *, NSData *> *> *)snapshot:(NSError **)error;
- (NSString *)text;
- (BOOL)restore:(NSArray<NSDictionary<NSString *, NSData *> *> *)snapshot ifUnchanged:(NSInteger)count;
@end

@interface WLPasteboard : NSObject <WLClipboard>
- (instancetype)initWithPasteboard:(NSPasteboard *)pasteboard;
@end

// No keyboard or clipboard side effects until captureForPID is explicitly called.
@interface WLCopyCapture : NSObject
@property(nonatomic,readonly) BOOL running;
- (instancetype)initWithClipboard:(id<WLClipboard>)clipboard frontPID:(pid_t (^)(void))frontPID sendCopy:(BOOL (^)(pid_t))sendCopy;
- (void)captureForPID:(pid_t)pid completion:(void (^)(NSString *, NSError *))completion;
- (void)cancel;
@end
