#import <Cocoa/Cocoa.h>

extern NSString * const WLDefaultBaseURL;
extern NSString * const WLDefaultPrompt;
extern const NSUInteger WLMaximumTextLength;
NSString *WLTrim(NSString *value);
NSURL *WLEndpoint(NSString *base, NSError **error);
NSError *WLError(NSString *message);
NSString *WLParseResponse(NSData *data, NSInteger status, NSString *key, NSError **error);
NSMutableURLRequest *WLRequest(NSDictionary *settings, NSString *key, NSString *text, NSError **error);
NSRect WLClampedBubbleFrame(NSPoint pointer, NSRect screen);

@interface WLSettings : NSObject
@property(nonatomic, strong) NSUserDefaults *defaults;
- (NSDictionary *)values;
- (void)saveValues:(NSDictionary *)values;
- (NSString *)keyForBase:(NSString *)base error:(NSError **)error;
- (BOOL)saveKey:(NSString *)key base:(NSString *)base error:(NSError **)error;
@end

@interface WLClient : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic, strong) NSURLSession *session;
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration;
- (NSURLSessionDataTask *)translate:(NSString *)text settings:(NSDictionary *)settings key:(NSString *)key completion:(void (^)(NSString *, NSError *))completion;
@end

@interface WLSelection : NSObject
+ (NSString *)selectedTextForPID:(pid_t)pid atPoint:(NSPoint)point;
+ (BOOL)focusedFieldIsSecureForPID:(pid_t)pid;
@end
