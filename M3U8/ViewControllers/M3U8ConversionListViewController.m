//
//  M3U8ConversionListViewController.m
//  M3U8Converter
//

#import "M3U8ConversionListViewController.h"
#import "M3U8ConversionService.h"
#import "M3U8FileManagerService.h"
#import "M3U8ConversionTask.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface M3U8ConversionListViewController () <UITableViewDelegate, UITableViewDataSource, M3U8ConversionServiceDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<M3U8ConversionTask *> *tasks;
@property (nonatomic, strong) M3U8ConversionService *conversionService;
@property (nonatomic, strong) UIBarButtonItem *startAllButton;
@property (nonatomic, strong) UIBarButtonItem *clearButton;
@property (nonatomic, strong) NSMutableSet<NSString *> *autoResumeTaskIds;

@end

@implementation M3U8ConversionListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSLog(@"[转换列表] viewDidLoad 被调用");

    self.title = @"转换列表";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tasks = [NSMutableArray array];
    self.conversionService = [M3U8ConversionService sharedService];
    self.conversionService.delegate = self;
    self.autoResumeTaskIds = [NSMutableSet set];

    [self setupUI];
    [self setupNavigationBar];
    [self registerNotifications];
    [self loadTasksFromDisk];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSLog(@"[转换列表] viewWillAppear 被调用，当前任务数: %lu", (unsigned long)self.tasks.count);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 92;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TaskCell"];
    [self.view addSubview:self.tableView];
}

- (void)setupNavigationBar {
    // 开始全部按钮
    self.startAllButton = [[UIBarButtonItem alloc] initWithTitle:@"开始全部"
                                                           style:UIBarButtonItemStylePlain
                                                          target:self
                                                          action:@selector(startAllTasks)];

    // 清空已完成按钮
    self.clearButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                     target:self
                                                                     action:@selector(clearCompleted)];

    self.navigationItem.rightBarButtonItems = @[self.clearButton, self.startAllButton];
}

- (void)registerNotifications {
    NSLog(@"[转换列表] 注册通知监听器");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAddTaskNotification:)
                                                 name:@"AddConversionTask"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAppDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAppWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

#pragma mark - Actions

- (void)startAllTasks {
    for (M3U8ConversionTask *task in self.tasks) {
        if (task.status == M3U8ConversionStatusPending ||
            task.status == M3U8ConversionStatusPaused) {
            [self startConversionForTask:task];
        }
    }
}

- (void)pauseTask:(M3U8ConversionTask *)task
           reason:(NSString *)reason
       autoResume:(BOOL)autoResume {
    [self.conversionService cancelConversionForTaskId:task.taskId];
    task.status = M3U8ConversionStatusPaused;
    task.errorMessage = reason;
    if (autoResume) {
        [self.autoResumeTaskIds addObject:task.taskId];
    }
}

- (void)handleAppDidEnterBackground {
    BOOL updated = NO;
    for (M3U8ConversionTask *task in self.tasks) {
        if (task.status == M3U8ConversionStatusConverting) {
            [self pauseTask:task
                     reason:@"已进入后台，转码已暂停。"
                 autoResume:NO];
            updated = YES;
        }
    }
    if (updated) {
        [self.tableView reloadData];
        [self saveTasksToDisk];
    }
}

- (void)handleAppWillEnterForeground {
    [self.autoResumeTaskIds removeAllObjects];
}

- (void)clearCompleted {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"清理缓存"
                                                                     message:@"将删除所有缓存文件并移除已完成任务，是否继续？"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"确认删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *cacheError = nil;
        [[M3U8FileManagerService sharedService] clearSourceCacheWithError:&cacheError];
        NSError *convertedError = nil;
        [[M3U8FileManagerService sharedService] clearConvertedDirectoryWithError:&convertedError];

        NSMutableArray *completedTasks = [NSMutableArray array];
        for (M3U8ConversionTask *task in self.tasks) {
            if ([task isFinished]) {
                [completedTasks addObject:task];
            }
        }

        [self.tasks removeObjectsInArray:completedTasks];
        [self.tableView reloadData];
        [self saveTasksToDisk];

        if (cacheError || convertedError) {
            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"清理失败"
                                                                                message:cacheError.localizedDescription ?: convertedError.localizedDescription ?: @"无法清理缓存"
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:errorAlert animated:YES completion:nil];
        }

        [self.conversionService removeAllSystemDownloadsWithCompletion:^(NSError * _Nullable error) {
            if (error) {
                UIAlertController *fallback = [UIAlertController alertControllerWithTitle:@"系统未返回可删除项目"
                                                                                   message:@"是否使用文件系统方式强制清理系统下载缓存？"
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                [fallback addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                [fallback addAction:[UIAlertAction actionWithTitle:@"强制清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                    NSError *userManagedError = nil;
                    [[M3U8FileManagerService sharedService] clearUserManagedAssetsWithError:&userManagedError];
                    if (userManagedError) {
                        UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"清理失败"
                                                                                            message:userManagedError.localizedDescription ?: @"无法清理系统下载缓存"
                                                                                     preferredStyle:UIAlertControllerStyleAlert];
                        [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:errorAlert animated:YES completion:nil];
                    }
                }]];
                [self presentViewController:fallback animated:YES completion:nil];
            }
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)startConversionForTask:(M3U8ConversionTask *)task {
    NSLog(@"[转换列表] 开始转换任务: %@", task.taskId);
    task.status = M3U8ConversionStatusPreparing;
    task.errorMessage = nil;
    task.convertProgress = 0.0;
    [self updateTaskInTable:task];
    [self saveTasksToDisk];

    __weak typeof(self) weakSelf = self;
    [self.conversionService startConversionForTask:task
                                          progress:^(NSString *taskId, CGFloat progress) {
        // 更新进度（分阶段，保持单调）
        for (M3U8ConversionTask *t in weakSelf.tasks) {
            if ([t.taskId isEqualToString:taskId]) {
                if (t.status == M3U8ConversionStatusPreparing) {
                    t.downloadProgress = MAX(t.downloadProgress, progress);
                    NSLog(@"[转换列表] 任务 %@ 下载进度: %.2f%%", taskId, t.downloadProgress * 100);
                } else {
                    t.convertProgress = MAX(t.convertProgress, progress);
                    NSLog(@"[转换列表] 任务 %@ 转换进度: %.2f%%", taskId, t.convertProgress * 100);
                }
                [weakSelf updateTaskInTable:t];
                break;
            }
        }
    } completion:^(NSString *taskId, BOOL success, NSError *error) {
        // 转换完成
        NSLog(@"[转换列表] 任务 %@ 完成，成功: %d, 错误: %@", taskId, success, error);
        for (M3U8ConversionTask *t in weakSelf.tasks) {
            if ([t.taskId isEqualToString:taskId]) {
                if (t.status == M3U8ConversionStatusPaused ||
                    t.status == M3U8ConversionStatusCancelled) {
                    [weakSelf updateTaskInTable:t];
                    [weakSelf saveTasksToDisk];
                    break;
                }
                if (success) {
                    t.status = M3U8ConversionStatusCompleted;
                    t.completedAt = [NSDate date];
                    t.downloadProgress = 1.0;
                    t.convertProgress = 1.0;
                } else {
                    t.status = M3U8ConversionStatusFailed;
                    t.errorMessage = error.localizedDescription;
                }
                [weakSelf updateTaskInTable:t];
                [weakSelf saveTasksToDisk];
                break;
            }
        }
    }];
}

- (void)cancelTask:(M3U8ConversionTask *)task {
    [self.conversionService cancelConversionForTaskId:task.taskId];
    task.status = M3U8ConversionStatusCancelled;
    [self updateTaskInTable:task];
    [self saveTasksToDisk];
}

- (void)retryTask:(M3U8ConversionTask *)task {
    task.status = M3U8ConversionStatusPending;
    BOOL hasLocalSource = task.localSourceURL && [[NSFileManager defaultManager] fileExistsAtPath:task.localSourceURL.path];
    BOOL hasPackage = task.localPackageURL && [[NSFileManager defaultManager] fileExistsAtPath:task.localPackageURL.path];
    task.downloadProgress = (hasLocalSource || hasPackage) ? 1.0 : 0.0;
    task.convertProgress = 0.0;
    task.errorMessage = nil;
    [self updateTaskInTable:task];
    [self saveTasksToDisk];
    [self startConversionForTask:task];
}

#pragma mark - Notification Handlers

- (void)handleAddTaskNotification:(NSNotification *)notification {
    M3U8ConversionTask *task = notification.object;
    NSLog(@"[转换列表] 收到添加任务通知: %@", task);
    if (task) {
        [self.tasks addObject:task];
        NSLog(@"[转换列表] 任务已添加到列表，当前任务数: %lu", (unsigned long)self.tasks.count);

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
            NSLog(@"[转换列表] TableView 已刷新");

            [self saveTasksToDisk];
            // 自动开始转换
            [self startConversionForTask:task];
        });
    } else {
        NSLog(@"[转换列表] 警告：收到空任务！");
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.tasks.count == 0) {
        // 显示空状态
        UILabel *emptyLabel = [[UILabel alloc] initWithFrame:self.tableView.bounds];
        emptyLabel.text = @"暂无转换任务\n\n请前往首页添加文件";
        emptyLabel.textColor = [UIColor secondaryLabelColor];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.numberOfLines = 0;
        self.tableView.backgroundView = emptyLabel;
    } else {
        self.tableView.backgroundView = nil;
    }

    return self.tasks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TaskCell" forIndexPath:indexPath];

    M3U8ConversionTask *task = self.tasks[indexPath.row];

    // 配置 cell（简化版本）
    [self configureCell:cell withTask:task];

    return cell;
}

- (void)configureCell:(UITableViewCell *)cell withTask:(M3U8ConversionTask *)task {
    // 清除之前的子视图
    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }

    // 文件名标签
    UILabel *fileNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, cell.contentView.bounds.size.width - 30, 20)];
    fileNameLabel.text = [task fileName];
    fileNameLabel.font = [UIFont boldSystemFontOfSize:16];
    [cell.contentView addSubview:fileNameLabel];

    // 状态标签
    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 34, 150, 16)];
    statusLabel.text = [task statusDisplayName];
    statusLabel.font = [UIFont systemFontOfSize:14];
    statusLabel.textColor = [self colorForStatus:task.status];
    [cell.contentView addSubview:statusLabel];

    BOOL showProgress = task.status == M3U8ConversionStatusPending ||
                        task.status == M3U8ConversionStatusPreparing ||
                        task.status == M3U8ConversionStatusConverting ||
                        task.status == M3U8ConversionStatusPaused;
    if (showProgress) {
        UILabel *progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 68, cell.contentView.bounds.size.width - 30, 14)];
        progressLabel.text = [NSString stringWithFormat:@"下载 %.0f%%   转换 %.0f%%",
                              task.downloadProgress * 100,
                              task.convertProgress * 100];
        progressLabel.font = [UIFont systemFontOfSize:12];
        progressLabel.textColor = [UIColor secondaryLabelColor];
        [cell.contentView addSubview:progressLabel];

        UIProgressView *progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(15, 56, cell.contentView.bounds.size.width - 30, 8)];
        if (task.status == M3U8ConversionStatusConverting) {
            progressView.progressTintColor = [UIColor systemGreenColor];
            progressView.progress = task.convertProgress;
        } else {
            progressView.progressTintColor = [UIColor systemBlueColor];
            progressView.progress = task.downloadProgress;
        }
        [cell.contentView addSubview:progressView];
    }

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

- (UIColor *)colorForStatus:(M3U8ConversionStatus)status {
    switch (status) {
        case M3U8ConversionStatusPending:
            return [UIColor systemGrayColor];
        case M3U8ConversionStatusPreparing:
        case M3U8ConversionStatusConverting:
            return [UIColor systemBlueColor];
        case M3U8ConversionStatusPaused:
            return [UIColor systemGrayColor];
        case M3U8ConversionStatusCompleted:
            return [UIColor systemGreenColor];
        case M3U8ConversionStatusFailed:
            return [UIColor systemRedColor];
        case M3U8ConversionStatusCancelled:
            return [UIColor systemOrangeColor];
    }
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    M3U8ConversionTask *task = self.tasks[indexPath.row];
    if (task.status == M3U8ConversionStatusCompleted ||
        task.status == M3U8ConversionStatusFailed) {
        return 60.0;
    }
    return 92.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    M3U8ConversionTask *task = self.tasks[indexPath.row];

    // 显示操作选项
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[task fileName]
                                                                   message:[task statusDisplayName]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if ([task isActive]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"暂停" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self pauseTask:task reason:@"任务已手动暂停。" autoResume:NO];
            [self.tableView reloadData];
            [self saveTasksToDisk];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消转换" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self cancelTask:task];
        }]];
        if (task.status == M3U8ConversionStatusPreparing && task.downloadProgress >= 1.0) {
            [alert addAction:[UIAlertAction actionWithTitle:@"开始转码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                task.convertProgress = 0.0;
                task.errorMessage = nil;
                [self updateTaskInTable:task];
                [self saveTasksToDisk];
                [self startConversionForTask:task];
            }]];
        }
    } else if (task.status == M3U8ConversionStatusCompleted) {
        [alert addAction:[UIAlertAction actionWithTitle:@"查看视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self playTaskOutput:task];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self shareTaskOutput:task];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"重新转码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            task.convertProgress = 0.0;
            task.errorMessage = nil;
            [self updateTaskInTable:task];
            [self saveTasksToDisk];
            [self startConversionForTask:task];
        }]];
    } else if (task.status == M3U8ConversionStatusPaused) {
        [alert addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self startConversionForTask:task];
        }]];
        if (task.downloadProgress >= 1.0) {
            [alert addAction:[UIAlertAction actionWithTitle:@"开始转码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                task.convertProgress = 0.0;
                task.errorMessage = nil;
                [self updateTaskInTable:task];
                [self saveTasksToDisk];
                [self startConversionForTask:task];
            }]];
        }
    } else if (task.status == M3U8ConversionStatusPending) {
        [alert addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self startConversionForTask:task];
        }]];
    } else if (task.status == M3U8ConversionStatusFailed) {
        [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self retryTask:task];
        }]];
    } else if (task.status == M3U8ConversionStatusCancelled) {
        [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self retryTask:task];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.conversionService removeSystemDownloadsForTask:task completion:nil];
        M3U8FileManagerService *fileManager = [M3U8FileManagerService sharedService];
        if (task.outputURL) {
            [fileManager deleteFileAtURL:task.outputURL error:nil];
        }
        if (task.localPackageURL) {
            [fileManager deleteFileAtURL:task.localPackageURL error:nil];
        }
        if (task.localSourceURL) {
            [fileManager deleteFileAtURL:task.localSourceURL error:nil];
        }
        [self.tasks removeObject:task];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [self saveTasksToDisk];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - M3U8ConversionServiceDelegate

- (void)conversionService:(M3U8ConversionService *)service
        didUpdateProgress:(CGFloat)progress
                forTaskId:(NSString *)taskId {
    // 更新已在 progress block 中处理
}

- (void)conversionService:(M3U8ConversionService *)service
didCompleteConversionForTaskId:(NSString *)taskId
                outputURL:(NSURL *)outputURL {
    NSLog(@"Conversion completed: %@", outputURL);
}

- (void)conversionService:(M3U8ConversionService *)service
didFailConversionForTaskId:(NSString *)taskId
                    error:(NSError *)error {
    NSLog(@"Conversion failed: %@", error.localizedDescription);
}

#pragma mark - Helper Methods

- (void)updateTaskInTable:(M3U8ConversionTask *)task {
    NSInteger index = [self.tasks indexOfObject:task];
    if (index != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)playTaskOutput:(M3U8ConversionTask *)task {
    NSURL *outputURL = task.outputURL;
    if (!outputURL || ![[NSFileManager defaultManager] fileExistsAtPath:outputURL.path]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"文件不存在"
                                                                       message:@"未找到已转换的视频文件，请重新转换。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    AVPlayer *player = [AVPlayer playerWithURL:outputURL];
    AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
    playerVC.player = player;
    [self presentViewController:playerVC animated:YES completion:^{
        [player play];
    }];
}

- (void)shareTaskOutput:(M3U8ConversionTask *)task {
    NSURL *outputURL = task.outputURL;
    if (!outputURL || ![[NSFileManager defaultManager] fileExistsAtPath:outputURL.path]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"文件不存在"
                                                                       message:@"未找到已转换的视频文件，请重新转换。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[outputURL] applicationActivities:nil];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UIPopoverPresentationController *popover = activity.popoverPresentationController;
        popover.sourceView = self.view;
        popover.sourceRect = self.view.bounds;
    }
    [self presentViewController:activity animated:YES completion:nil];
}

#pragma mark - Persistence

- (NSURL *)tasksArchiveURL {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                  inDomains:NSUserDomainMask] firstObject];
    return [documentsURL URLByAppendingPathComponent:@"conversion_tasks.dat"];
}

- (void)saveTasksToDisk {
    NSError *archiveError = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.tasks
                                         requiringSecureCoding:YES
                                                         error:&archiveError];
    if (!data) {
        NSLog(@"[转换列表] 保存任务失败: %@", archiveError);
        return;
    }
    NSError *writeError = nil;
    BOOL ok = [data writeToURL:[self tasksArchiveURL] options:NSDataWritingAtomic error:&writeError];
    if (!ok) {
        NSLog(@"[转换列表] 写入任务文件失败: %@", writeError);
    }
}

- (void)loadTasksFromDisk {
    NSURL *archiveURL = [self tasksArchiveURL];
    NSData *data = [NSData dataWithContentsOfURL:archiveURL];
    if (data.length == 0) {
        return;
    }
    NSError *error = nil;
    NSSet<Class> *allowed = [NSSet setWithObjects:
                             [NSArray class],
                             [M3U8ConversionTask class],
                             [NSURL class],
                             [NSDate class],
                             [NSString class], nil];
    NSArray<M3U8ConversionTask *> *saved = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowed
                                                                               fromData:data
                                                                                  error:&error];
    if (!saved) {
        NSLog(@"[转换列表] 读取任务失败: %@", error);
        return;
    }
    self.tasks = [saved mutableCopy];
    for (M3U8ConversionTask *task in self.tasks) {
        if ([task isActive]) {
            task.status = M3U8ConversionStatusFailed;
            task.convertProgress = 0;
            task.errorMessage = @"应用已重启，任务中断，可点击重试。";
        }
    }
    [self.tableView reloadData];
}

@end
