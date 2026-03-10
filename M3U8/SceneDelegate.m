//
//  SceneDelegate.m
//  M3U8
//
//  Created by YLRS on 3/3/26.
//

#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "M3U8MainViewController.h"
#import "M3U8ConversionTask.h"

@interface SceneDelegate ()

@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // 设置 M3U8MainViewController 为首页
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    M3U8MainViewController *mainViewController = [[M3U8MainViewController alloc] init];
    self.window.rootViewController = mainViewController;

    [self.window makeKeyAndVisible];

    if (connectionOptions.URLContexts.count > 0) {
        UIOpenURLContext *context = connectionOptions.URLContexts.allObjects.firstObject;
        [self handleIncomingURL:context.URL];
    }
}


- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.

    // Save changes in the application's managed object context when the application transitions to the background.
    [(AppDelegate *)UIApplication.sharedApplication.delegate saveContext];
}

#pragma mark - URL Handling

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    UIOpenURLContext *context = URLContexts.allObjects.firstObject;
    if (context.URL) {
        [self handleIncomingURL:context.URL];
    }
}

- (void)handleIncomingURL:(NSURL *)url {
    if (![[url.scheme lowercaseString] isEqualToString:@"m3u8converter"]) {
        return;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *targetURLString = nil;
    NSString *title = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"url"]) {
            targetURLString = item.value;
        } else if ([item.name isEqualToString:@"title"]) {
            title = item.value;
        }
    }

    if (targetURLString.length == 0) {
        return;
    }

    NSURL *targetURL = [NSURL URLWithString:targetURLString];
    if (!targetURL) {
        return;
    }

    M3U8ConversionTask *task = [[M3U8ConversionTask alloc] initWithSourceURL:targetURL
                                                                   sourceType:M3U8InputSourceTypeRemoteURL];
    task.customTitle = title;

    UITabBarController *tabBar = (UITabBarController *)self.window.rootViewController;
    if ([tabBar isKindOfClass:[UITabBarController class]]) {
        tabBar.selectedIndex = 1;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AddConversionTask" object:task];
    });
}

@end
