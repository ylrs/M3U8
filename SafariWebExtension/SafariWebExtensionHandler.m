//
//  SafariWebExtensionHandler.m
//  M3U8Converter
//

#import <SafariServices/SafariServices.h>

@interface SafariWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation SafariWebExtensionHandler

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    NSExtensionItem *item = [[NSExtensionItem alloc] init];
    item.userInfo = @{};
    [context completeRequestReturningItems:@[item] completionHandler:nil];
}

@end
