//
//  M3U8HomeViewController.m
//  M3U8Converter
//

#import "M3U8HomeViewController.h"
#import "M3U8ConversionService.h"
#import "M3U8FileManagerService.h"
#import "M3U8ConversionTask.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface M3U8HomeViewController () <UIDocumentPickerDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStackView;
@property (nonatomic, strong) UITextField *urlTextField;

@end

@implementation M3U8HomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"M3U8 转 MP4";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self setupUI];
}

#pragma mark - UI Setup

- (void)setupUI {
    // ScrollView
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    // ContentStackView
    self.contentStackView = [[UIStackView alloc] init];
    self.contentStackView.axis = UILayoutConstraintAxisVertical;
    self.contentStackView.spacing = 20;
    self.contentStackView.alignment = UIStackViewAlignmentFill;
    self.contentStackView.distribution = UIStackViewDistributionFill;
    self.contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStackView];

    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"选择输入方式";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentStackView addArrangedSubview:titleLabel];

    // 按钮卡片容器
    UIView *cardsContainer = [[UIView alloc] init];
    cardsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStackView addArrangedSubview:cardsContainer];

    // 三个功能卡片
    [self addCardButtonToContainer:cardsContainer
                             title:@"选择本地文件"
                              icon:@"folder"
                            action:@selector(selectLocalFile)
                          yOffset:0];

    [self addCardButtonToContainer:cardsContainer
                             title:@"输入 URL 链接"
                              icon:@"link"
                            action:@selector(inputURL)
                          yOffset:140];

    [self addCardButtonToContainer:cardsContainer
                             title:@"从其他应用分享"
                              icon:@"square.and.arrow.down"
                            action:@selector(showShareInstructions)
                          yOffset:280];

    [self addCardButtonToContainer:cardsContainer
                             title:@"测试示例链接"
                              icon:@"play.circle"
                            action:@selector(useExampleURL)
                          yOffset:420];

    // 设置约束
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentStackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20],
        [self.contentStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:20],
        [self.contentStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-20],
        [self.contentStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20],
        [self.contentStackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-40],

        [cardsContainer.heightAnchor constraintEqualToConstant:540]
    ]];
}

- (void)addCardButtonToContainer:(UIView *)container
                           title:(NSString *)title
                            icon:(NSString *)iconName
                          action:(SEL)action
                        yOffset:(CGFloat)yOffset {

    // 卡片容器
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 2);
    card.layer.shadowRadius = 4;
    card.layer.shadowOpacity = 0.1;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:card];

    // 图标
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tintColor = [UIColor systemBlueColor];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:iconView];

    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleLabel];

    // 添加点击手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:action];
    [card addGestureRecognizer:tapGesture];

    // 约束
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:yOffset],
        [card.heightAnchor constraintEqualToConstant:120],

        [iconView.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [iconView.widthAnchor constraintEqualToConstant:50],
        [iconView.heightAnchor constraintEqualToConstant:50],

        [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:15],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20]
    ]];
}

#pragma mark - Actions

- (void)selectLocalFile {
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *m3u8Type = [UTType typeWithIdentifier:@"com.apple.mpegurl"];
    if (m3u8Type) {
        [types addObject:m3u8Type];
    }
    [types addObject:UTTypeMovie];
    [types addObject:UTTypeVideo];
    [types addObject:UTTypeMPEG4Movie];
    [types addObject:UTTypeMPEG2TransportStream];
    [types addObject:UTTypeAudio];
    [types addObject:UTTypeData];

    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)inputURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入 M3U8 URL"
                                                                   message:@"请输入在线 m3u8 视频链接"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/video.m3u8";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始转换" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *urlString = textField.text;
        [self handleURLInput:urlString];
    }];
    UIAlertAction *pasteAction = [UIAlertAction actionWithTitle:@"使用剪贴板" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *pasteString = [UIPasteboard generalPasteboard].string;
        [self handleURLInput:pasteString];
    }];

    [alert addAction:cancelAction];
    [alert addAction:pasteAction];
    [alert addAction:confirmAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showShareInstructions {
    NSString *pasteString = [UIPasteboard generalPasteboard].string;
    BOOL hasPaste = pasteString.length > 0;
    NSString *message = @"使用方法：\n\n1. 在 Safari 或其他应用中找到 m3u8 链接\n2. 点击\"分享\"按钮\n3. 选择\"M3U8 Converter\"\n4. 回到本应用查看转换进度";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"接收分享的文件"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (hasPaste) {
        [alert addAction:[UIAlertAction actionWithTitle:@"使用剪贴板链接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self handleURLInput:pasteString];
        }]];
    }
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)useExampleURL {
    NSString *exampleURL = @"https://sf1-cdn-tos.huoshanstatic.com/obj/media-fe/xgplayer_doc_video/hls/xgplayer-demo.m3u8";

//    NSString *exampleURL = @"https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"使用示例链接"
                                                                   message:@"这是一个测试用的 M3U8 视频链接"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始转换" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self handleURLInput:exampleURL];
    }];

    [alert addAction:cancelAction];
    [alert addAction:confirmAction];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - File Handling

- (void)handleURLInput:(NSString *)urlString {
    NSString *normalized = [self normalizedURLString:urlString];
    if (normalized.length == 0) {
        [self showErrorAlert:@"请输入有效的 URL"];
        return;
    }
    NSURL *url = [NSURL URLWithString:normalized];
    if (!url || !url.host.length) {
        [self showErrorAlert:@"URL 格式不正确"];
        return;
    }

    NSLog(@"[首页] 创建转换任务: %@", normalized);
    M3U8ConversionTask *task = [[M3U8ConversionTask alloc] initWithSourceURL:url
                                                                   sourceType:M3U8InputSourceTypeRemoteURL];
    NSLog(@"[首页] 任务创建成功，TaskID: %@", task.taskId);

    // 先切换到转换列表 Tab，确保视图已加载
    self.tabBarController.selectedIndex = 1;

    // 延迟发送通知，确保转换列表已经加载完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AddConversionTask" object:task];
        NSLog(@"[首页] 已发送通知 AddConversionTask");
    });

    [self showSuccessAlert:@"任务已添加到转换列表"];
}

- (void)handleSelectedFiles:(NSArray<NSURL *> *)urls {
    NSMutableArray<M3U8ConversionTask *> *tasks = [NSMutableArray array];

    for (NSURL *url in urls) {
        // 开始访问安全作用域资源
        [url startAccessingSecurityScopedResource];

        NSError *copyError = nil;
        NSURL *cachedURL = [[M3U8FileManagerService sharedService] copyFileToCache:url error:&copyError];
        if (cachedURL) {
            M3U8ConversionTask *task = [[M3U8ConversionTask alloc] initWithSourceURL:cachedURL
                                                                           sourceType:M3U8InputSourceTypeLocalFile];
            [tasks addObject:task];
        } else {
            NSLog(@"[首页] 复制文件失败: %@", copyError);
        }

        // 停止访问
        [url stopAccessingSecurityScopedResource];
    }

    if (tasks.count == 0) {
        [self showErrorAlert:@"未能读取所选文件，请检查权限或文件类型"];
        return;
    }

    // 先切换到转换列表 Tab
    self.tabBarController.selectedIndex = 1;

    // 延迟发送通知
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (M3U8ConversionTask *task in tasks) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"AddConversionTask" object:task];
        }
    });

    NSString *message = [NSString stringWithFormat:@"已添加 %lu 个文件到转换列表", (unsigned long)urls.count];
    [self showSuccessAlert:message];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self handleSelectedFiles:urls];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"Document picker cancelled");
}

#pragma mark - Helper Methods

- (void)showErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"错误"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSuccessAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"成功"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)normalizedURLString:(NSString *)input {
    NSString *trimmed = [[input ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (trimmed.length == 0) {
        return @"";
    }
    if ([trimmed hasPrefix:@"//"]) {
        return [@"https:" stringByAppendingString:trimmed];
    }
    NSURL *testURL = [NSURL URLWithString:trimmed];
    if (testURL.scheme.length == 0) {
        return [@"https://" stringByAppendingString:trimmed];
    }
    return trimmed;
}

@end
