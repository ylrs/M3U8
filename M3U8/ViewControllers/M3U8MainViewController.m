//
//  M3U8MainViewController.m
//  M3U8Converter
//

#import "M3U8MainViewController.h"
#import "M3U8HomeViewController.h"
#import "M3U8ConversionListViewController.h"
#import "M3U8HistoryViewController.h"

@interface M3U8MainViewController ()

@end

@implementation M3U8MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 设置 Tab Bar 样式
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.tabBar.tintColor = [UIColor systemBlueColor];

    // 创建各个 Tab 的视图控制器
    [self setupViewControllers];
}

#pragma mark - Private Methods

- (void)setupViewControllers {
    // 首页
    M3U8HomeViewController *homeVC = [[M3U8HomeViewController alloc] init];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:homeVC];
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"首页"
                                                       image:[UIImage systemImageNamed:@"house"]
                                               selectedImage:[UIImage systemImageNamed:@"house.fill"]];

    // 转换列表
    M3U8ConversionListViewController *conversionVC = [[M3U8ConversionListViewController alloc] init];
    UINavigationController *conversionNav = [[UINavigationController alloc] initWithRootViewController:conversionVC];
    conversionNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"转换"
                                                             image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
                                                     selectedImage:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath.circle.fill"]];

    // 历史记录
    M3U8HistoryViewController *historyVC = [[M3U8HistoryViewController alloc] init];
    UINavigationController *historyNav = [[UINavigationController alloc] initWithRootViewController:historyVC];
    historyNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"历史"
                                                          image:[UIImage systemImageNamed:@"clock"]
                                                  selectedImage:[UIImage systemImageNamed:@"clock.fill"]];

    // 设置 Tab Bar Controllers
    self.viewControllers = @[homeNav, conversionNav, historyNav];
}

@end
