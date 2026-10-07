#import "WLApp.h"
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSApplication *application=NSApplication.sharedApplication;
        WLAppDelegate *delegate=[WLAppDelegate new]; application.delegate=delegate;
        if (argc==3 && (strcmp(argv[1],"--render")==0 || strcmp(argv[1],"--render-settings")==0)) {
            [application setActivationPolicy:NSApplicationActivationPolicyProhibited];
            [delegate renderPreview:@(argv[2]) settings:strcmp(argv[1],"--render-settings")==0]; return 0;
        }
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
    }
    return 0;
}
