#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>

// Build icon assets offscreen without registering a desktop application.
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc!=2) return 1;
        NSString *directory=@(argv[1]);
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSNumber *number in @[@16,@32,@128,@256,@512]) {
            NSInteger size=number.integerValue;
            for (NSInteger scale=1;scale<=2;scale++) {
                NSInteger pixels=size*scale; CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
                CGContextRef context=CGBitmapContextCreate(NULL,pixels,pixels,8,pixels*4,space,kCGImageAlphaPremultipliedLast);
                CGColorSpaceRelease(space); if (!context) return 2;
                CGContextSetRGBFillColor(context,.20,.34,.92,1);
                CGPathRef path=CGPathCreateWithRoundedRect(CGRectMake(pixels*.08,pixels*.08,pixels*.84,pixels*.84),pixels*.23,pixels*.23,NULL);
                CGContextAddPath(context,path); CGContextFillPath(context); CGPathRelease(path);
                CTFontRef font=CTFontCreateWithName(CFSTR("PingFangSC-Semibold"),pixels*.54,NULL);
                CGColorRef white=CGColorCreateGenericRGB(1,1,1,1);
                NSDictionary *attrs=@{(__bridge id)kCTFontAttributeName:(__bridge id)font,(__bridge id)kCTForegroundColorAttributeName:(__bridge id)white};
                NSAttributedString *text=[[NSAttributedString alloc] initWithString:@"译" attributes:attrs]; CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
                CGRect bounds=CTLineGetBoundsWithOptions(line,kCTLineBoundsUseGlyphPathBounds);
                CGContextSetTextPosition(context,(pixels-bounds.size.width)/2-bounds.origin.x,(pixels-bounds.size.height)/2-bounds.origin.y);
                CTLineDraw(line,context); CFRelease(line); CFRelease(font); CGColorRelease(white);
                CGImageRef image=CGBitmapContextCreateImage(context);
                NSString *name=[NSString stringWithFormat:@"icon_%ldx%ld%@.png",(long)size,(long)size,scale==2 ? @"@2x" : @""];
                NSURL *url=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
                CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL);
                CGImageDestinationAddImage(destination,image,NULL); BOOL ok=CGImageDestinationFinalize(destination);
                CFRelease(destination); CGImageRelease(image); CGContextRelease(context); if (!ok) return 3;
            }
        }
    }
    return 0;
}
