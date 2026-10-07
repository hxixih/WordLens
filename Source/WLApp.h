#import "WLCore.h"

@interface WLAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate>
@property(nonatomic) BOOL previewMode;
- (void)buildMainWindow;
- (void)buildSettingsWindow;
- (void)renderPreview:(NSString *)path settings:(BOOL)settings;
@end
