//
//  M3U8ConversionService.m
//  M3U8Converter
//

#import "M3U8ConversionService.h"
#import "M3U8FFmpegService.h"
#import "M3U8FileManagerService.h"

@interface M3U8ConversionService () <AVAssetDownloadDelegate, NSURLSessionTaskDelegate>

@property (nonatomic, strong) NSMutableDictionary<NSString *, AVAssetExportSession *> *exportSessions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSTimer *> *progressTimers;
@property (nonatomic, strong) dispatch_queue_t conversionQueue;
@property (nonatomic, assign) NSInteger maxConcurrentTasks;
@property (nonatomic, strong) AVAssetDownloadURLSession *downloadSession;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AVAssetDownloadTask *> *downloadTasks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, M3U8ConversionProgressBlock> *downloadProgressBlocks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, M3U8ConversionCompletionBlock> *downloadCompletionBlocks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, M3U8ConversionTask *> *downloadTaskModels;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadProgressSnapshot;
@property (nonatomic, strong) NSSet<NSString *> *insecureTLSHosts;

@end

@implementation M3U8ConversionService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static M3U8ConversionService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _exportSessions = [NSMutableDictionary dictionary];
        _progressTimers = [NSMutableDictionary dictionary];
        _conversionQueue = dispatch_queue_create("com.m3u8converter.conversion", DISPATCH_QUEUE_CONCURRENT);
        _maxConcurrentTasks = 2;
        _downloadTasks = [NSMutableDictionary dictionary];
        _downloadProgressBlocks = [NSMutableDictionary dictionary];
        _downloadCompletionBlocks = [NSMutableDictionary dictionary];
        _downloadTaskModels = [NSMutableDictionary dictionary];
        _downloadProgressSnapshot = [NSMutableDictionary dictionary];
        _insecureTLSHosts = [NSSet setWithArray:@[@"sf1-cdn-tos.huoshanstatic.com"]];
        NSString *sessionId = @"com.m3u8converter.hlsdownload";
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sessionId];
        _downloadSession = [AVAssetDownloadURLSession sessionWithConfiguration:configuration
                                                           assetDownloadDelegate:self
                                                                  delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

#pragma mark - Public Methods

- (void)startConversionForTask:(M3U8ConversionTask *)task
                      progress:(M3U8ConversionProgressBlock)progressBlock
                    completion:(M3U8ConversionCompletionBlock)completionBlock {

    dispatch_async(self.conversionQueue, ^{
        [self convertM3U8ToMP4WithTask:task
                              progress:progressBlock
                            completion:completionBlock];
    });
}

- (void)cancelConversionForTaskId:(NSString *)taskId {
    // 取消 AVAsset 会话
    AVAssetExportSession *session = self.exportSessions[taskId];
    if (session) {
        [session cancelExport];
        [self.exportSessions removeObjectForKey:taskId];
    }

    // 取消进度计时器
    NSTimer *timer = self.progressTimers[taskId];
    if (timer) {
        [timer invalidate];
        [self.progressTimers removeObjectForKey:taskId];
    }

    // 取消下载任务
    AVAssetDownloadTask *downloadTask = self.downloadTasks[taskId];
    if (downloadTask) {
        [downloadTask cancel];
        [self.downloadTasks removeObjectForKey:taskId];
        [self.downloadProgressBlocks removeObjectForKey:taskId];
        [self.downloadCompletionBlocks removeObjectForKey:taskId];
        [self.downloadTaskModels removeObjectForKey:taskId];
    }

    // 取消 FFmpeg 会话
    [[M3U8FFmpegService sharedService] cancelConversionForTaskId:taskId];
}

- (void)cancelAllConversions {
    for (NSString *taskId in self.exportSessions.allKeys) {
        [self cancelConversionForTaskId:taskId];
    }
}

- (void)validateM3U8Source:(NSURL *)sourceURL completion:(void (^)(BOOL, NSError * _Nullable))completion {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];

    NSArray *keys = @[@"tracks", @"duration", @"playable"];
    [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:@"tracks" error:&error];

        if (status == AVKeyValueStatusLoaded) {
            BOOL isValid = asset.playable && asset.tracks.count > 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(isValid, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
        }
    }];
}

- (NSInteger)activeTasksCount {
    return self.exportSessions.count;
}

#pragma mark - Private Methods - Main Conversion Logic

- (void)convertM3U8ToMP4WithTask:(M3U8ConversionTask *)task
                        progress:(M3U8ConversionProgressBlock)progressBlock
                      completion:(M3U8ConversionCompletionBlock)completionBlock {

    NSLog(@"[转换服务] 开始转换任务 %@", task.taskId);
    NSLog(@"[转换服务] 源URL: %@", task.sourceURL);

    // 检测URL类型
    BOOL isRemoteURL = [task.sourceURL.scheme isEqualToString:@"http"] ||
                       [task.sourceURL.scheme isEqualToString:@"https"];
    BOOL isM3U8 = [task.sourceURL.pathExtension.lowercaseString isEqualToString:@"m3u8"] ||
                  [task.sourceURL.absoluteString containsString:@".m3u8"];

    NSLog(@"[转换服务] URL类型: %@ %@",
          isRemoteURL ? @"远程" : @"本地",
          isM3U8 ? @"M3U8流" : @"普通媒体");

    // 策略选择
    if (isRemoteURL && isM3U8) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (task.localSourceURL && [fm fileExistsAtPath:task.localSourceURL.path]) {
            task.status = M3U8ConversionStatusConverting;
            task.downloadProgress = 1.0;
            task.convertProgress = 0.0;
            NSLog(@"[转换服务] 使用已缓存播放列表，直接FFmpeg转码");
            [self convertWithFFmpeg:task progress:progressBlock completion:completionBlock];
            return;
        }
        if (task.localPackageURL && [fm fileExistsAtPath:task.localPackageURL.path]) {
            task.status = M3U8ConversionStatusPreparing;
            task.downloadProgress = 1.0;
            task.convertProgress = 0.0;
            NSLog(@"[转换服务] 使用已缓存下载包，准备本地播放列表");
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSError *prepareError = nil;
                NSURL *playlistURL = [self prepareLocalPlaylistForFFmpegFromPackage:task.localPackageURL
                                                                               task:task
                                                                              error:&prepareError];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!playlistURL) {
                        completionBlock(task.taskId, NO, prepareError ?: [NSError errorWithDomain:@"M3U8ConverterError"
                                                                                            code:-1019
                                                                                        userInfo:@{
                            NSLocalizedDescriptionKey: @"无法准备本地播放列表",
                            NSLocalizedFailureReasonErrorKey: @"请稍后重试或更换链接。"
                        }]);
                        return;
                    }
                    task.localSourceURL = playlistURL;
                    task.status = M3U8ConversionStatusConverting;
                    [self convertWithFFmpeg:task progress:progressBlock completion:completionBlock];
                });
            });
            return;
        }
        task.status = M3U8ConversionStatusPreparing;
        task.downloadProgress = 0.0;
        task.convertProgress = 0.0;
        NSLog(@"[转换服务] 策略: 远程HLS流 → AVFoundation下载 → FFmpeg本地转码");
        [self downloadWithAVFoundationThenConvertWithFFmpeg:task
                                                   progress:progressBlock
                                                 completion:completionBlock];
    } else {
        task.status = M3U8ConversionStatusConverting;
        task.downloadProgress = 1.0;
        task.convertProgress = 0.0;
        // 本地文件或非HLS流 - 优先尝试AVFoundation
        NSLog(@"[转换服务] 策略: 本地文件 → 尝试AVFoundation");
        [self convertWithAVFoundation:task
                             progress:progressBlock
                           completion:completionBlock];
    }
}

#pragma mark - FFmpeg Conversion

- (void)convertWithFFmpeg:(M3U8ConversionTask *)task
                 progress:(M3U8ConversionProgressBlock)progressBlock
               completion:(M3U8ConversionCompletionBlock)completionBlock {

    if (!task) {
        if (completionBlock) {
            completionBlock(@"", NO, [NSError errorWithDomain:@"M3U8ConverterError"
                                                         code:-1023
                                                     userInfo:@{
                NSLocalizedDescriptionKey: @"任务为空，无法转换",
                NSLocalizedFailureReasonErrorKey: @"任务可能已被释放或取消。"
            }]);
        }
        return;
    }
    task.status = M3U8ConversionStatusConverting;

    if (![M3U8FFmpegService isFFmpegAvailable]) {
        NSLog(@"[转换服务] ❌ FFmpeg未安装");

        NSError *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                             code:-1009
                                         userInfo:@{
            NSLocalizedDescriptionKey: @"FFmpeg未安装",
            NSLocalizedFailureReasonErrorKey: @"该视频需要FFmpeg来处理。\n\n请按照说明安装FFmpeg。"
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(task.taskId, NO, error);
        });
        return;
    }

    NSLog(@"[转换服务] ✓ 使用FFmpeg转换");
    NSLog(@"[转换服务] FFmpeg版本: %@", [M3U8FFmpegService ffmpegVersion]);

    M3U8FFmpegService *ffmpegService = [M3U8FFmpegService sharedService];

    [ffmpegService convertM3U8ToMP4WithTask:task
                                    quality:M3U8VideoQualityHigh
                                   progress:progressBlock
                                 completion:^(NSString *taskId, BOOL success, NSError *error) {
        if (success) {
            NSLog(@"[转换服务] ✓ FFmpeg转换成功");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupTempPlaylistIfNeededForTask:task];
                [self cleanLocalSourceIfNeededForTask:task];
                completionBlock(taskId, YES, nil);

                if ([self.delegate respondsToSelector:@selector(conversionService:didCompleteConversionForTaskId:outputURL:)]) {
                    [self.delegate conversionService:self
                         didCompleteConversionForTaskId:taskId
                                              outputURL:task.outputURL];
                }
            });
        } else {
            NSLog(@"[转换服务] ✗ FFmpeg转换失败: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupTempPlaylistIfNeededForTask:task];
                [self cleanLocalSourceIfNeededForTask:task];
                completionBlock(taskId, NO, error);

                if ([self.delegate respondsToSelector:@selector(conversionService:didFailConversionForTaskId:error:)]) {
                    [self.delegate conversionService:self
                         didFailConversionForTaskId:taskId
                                              error:error];
                }
            });
        }
    }];
}

#pragma mark - AVFoundation Conversion

- (void)convertWithAVFoundation:(M3U8ConversionTask *)task
                       progress:(M3U8ConversionProgressBlock)progressBlock
                     completion:(M3U8ConversionCompletionBlock)completionBlock {

    NSLog(@"[转换服务] 尝试使用AVFoundation转换");

    // 创建 AVURLAsset
    NSDictionary *options = @{
        AVURLAssetPreferPreciseDurationAndTimingKey: @YES
    };
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:task.sourceURL options:options];

    // 异步加载资源属性
    NSArray *keys = @[@"tracks", @"duration", @"playable", @"exportable"];
    [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:@"playable" error:&error];

        if (status != AVKeyValueStatusLoaded || !asset.playable) {
            NSLog(@"[转换服务] AVFoundation无法加载资源，尝试FFmpeg");
            [self convertWithFFmpeg:task progress:progressBlock completion:completionBlock];
            return;
        }

        NSLog(@"[转换服务] 资源加载成功，tracks: %lu", (unsigned long)asset.tracks.count);

        // 检查兼容的导出预设
        NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
        NSLog(@"[转换服务] 兼容预设: %@", compatiblePresets);

        // 选择预设
        NSArray *preferredPresets = @[
            AVAssetExportPresetHighestQuality,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetMediumQuality
        ];

        NSString *presetName = nil;
        for (NSString *preset in preferredPresets) {
            if ([compatiblePresets containsObject:preset]) {
                presetName = preset;
                break;
            }
        }

        if (!presetName) {
            NSLog(@"[转换服务] 没有兼容预设，尝试FFmpeg");
            [self convertWithFFmpeg:task progress:progressBlock completion:completionBlock];
            return;
        }

        NSLog(@"[转换服务] 使用预设: %@", presetName);

        // 创建导出会话
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset
                                                                                presetName:presetName];
        if (!exportSession) {
            NSLog(@"[转换服务] 无法创建导出会话，尝试FFmpeg");
            [self convertWithFFmpeg:task progress:progressBlock completion:completionBlock];
            return;
        }

        // 配置输出
        NSURL *outputURL = [self generateOutputURLForTask:task];
        exportSession.outputURL = outputURL;
        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.shouldOptimizeForNetworkUse = YES;

        // 保存会话
        self.exportSessions[task.taskId] = exportSession;

        // 启动进度监听
        [self startProgressMonitoringForTask:task.taskId
                              exportSession:exportSession
                               progressBlock:progressBlock];

        // 开始导出
        NSLog(@"[转换服务] 开始AVAssetExportSession导出");
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            // 停止进度监听
            [self stopProgressMonitoringForTaskId:task.taskId];
            [self.exportSessions removeObjectForKey:task.taskId];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                    NSLog(@"[转换服务] ✓ AVFoundation转换成功");
                    task.outputURL = outputURL;
                    completionBlock(task.taskId, YES, nil);

                    if ([self.delegate respondsToSelector:@selector(conversionService:didCompleteConversionForTaskId:outputURL:)]) {
                        [self.delegate conversionService:self
                             didCompleteConversionForTaskId:task.taskId
                                                  outputURL:outputURL];
                    }
                } else {
                    NSLog(@"[转换服务] ✗ AVFoundation失败: %@", exportSession.error);
                    NSLog(@"[转换服务] 错误码: %ld", (long)exportSession.error.code);

                    // 如果是编解码器问题，尝试FFmpeg
                    if (exportSession.error.code == -11838 ||
                        exportSession.error.code == -16976 ||
                        exportSession.error.code == -11800) {
                        NSLog(@"[转换服务] 检测到编解码器问题，尝试FFmpeg");
                        [self convertWithFFmpeg:task progress:progressBlock completion:completionBlock];
                    } else {
                        // 其他错误直接返回
                        completionBlock(task.taskId, NO, exportSession.error);

                        if ([self.delegate respondsToSelector:@selector(conversionService:didFailConversionForTaskId:error:)]) {
                            [self.delegate conversionService:self
                                 didFailConversionForTaskId:task.taskId
                                                      error:exportSession.error];
                        }
                    }
                }
            });
        }];
    }];
}

#pragma mark - AVFoundation Download + FFmpeg Convert

- (void)downloadWithAVFoundationThenConvertWithFFmpeg:(M3U8ConversionTask *)task
                                             progress:(M3U8ConversionProgressBlock)progressBlock
                                           completion:(M3U8ConversionCompletionBlock)completionBlock {
    if (![M3U8FFmpegService isFFmpegAvailable]) {
        NSError *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                             code:-1009
                                         userInfo:@{
            NSLocalizedDescriptionKey: @"FFmpeg未安装",
            NSLocalizedFailureReasonErrorKey: @"该视频需要FFmpeg来处理。\n\n请按照说明安装FFmpeg。"
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(task.taskId, NO, error);
        });
        return;
    }

    AVAssetDownloadTask *existing = self.downloadTasks[task.taskId];
    if (existing) {
        NSLog(@"[转换服务] 已存在下载任务，继续下载");
        [existing resume];
        return;
    }

    NSLog(@"[转换服务] 开始使用AVFoundation下载HLS");
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:task.sourceURL options:@{
        AVURLAssetPreferPreciseDurationAndTimingKey: @YES
    }];

    AVAssetDownloadTask *downloadTask = [self.downloadSession assetDownloadTaskWithURLAsset:asset
                                                                                  assetTitle:[task fileName]
                                                                           assetArtworkData:nil
                                                                                  options:nil];
    if (!downloadTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(task.taskId, NO, [NSError errorWithDomain:@"M3U8ConverterError"
                                                                code:-1018
                                                            userInfo:@{
                NSLocalizedDescriptionKey: @"AVFoundation无法创建下载任务",
                NSLocalizedFailureReasonErrorKey: @"请稍后重试。"
            }]);
        });
        return;
    }

    downloadTask.taskDescription = task.taskId;
    self.downloadTasks[task.taskId] = downloadTask;
    self.downloadProgressBlocks[task.taskId] = [progressBlock copy];
    self.downloadCompletionBlocks[task.taskId] = [completionBlock copy];
    self.downloadTaskModels[task.taskId] = task;
    if (!self.downloadProgressSnapshot[task.taskId]) {
        self.downloadProgressSnapshot[task.taskId] = @(task.downloadProgress);
    }

    [downloadTask resume];
}

#pragma mark - Helper Methods

- (void)startProgressMonitoringForTask:(NSString *)taskId
                        exportSession:(AVAssetExportSession *)exportSession
                         progressBlock:(M3U8ConversionProgressBlock)progressBlock {

    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                      repeats:YES
                                                        block:^(NSTimer * _Nonnull timer) {
        CGFloat progress = exportSession.progress;

        dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(taskId, progress);

            if ([self.delegate respondsToSelector:@selector(conversionService:didUpdateProgress:forTaskId:)]) {
                [self.delegate conversionService:self
                                didUpdateProgress:progress
                                        forTaskId:taskId];
            }
        });
    }];

    self.progressTimers[taskId] = timer;
}

#pragma mark - AVAssetDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask
      didLoadTimeRange:(CMTimeRange)timeRange
 totalTimeRangesLoaded:(NSArray<NSValue *> *)loadedTimeRanges
timeRangeExpectedToLoad:(CMTimeRange)timeRangeExpectedToLoad {
    NSString *taskId = assetDownloadTask.taskDescription;
    if (taskId.length == 0) {
        return;
    }

    NSTimeInterval expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration);
    if (isnan(expected) || expected <= 0) {
        return;
    }

    NSTimeInterval loaded = 0;
    for (NSValue *value in loadedTimeRanges) {
        CMTimeRange range = [value CMTimeRangeValue];
        loaded += CMTimeGetSeconds(range.duration);
    }

    CGFloat progress = (CGFloat)(loaded / expected);
    progress = MIN(MAX(progress, 0.0), 1.0);

    M3U8ConversionTask *task = self.downloadTaskModels[taskId];
    if (task) {
        task.status = M3U8ConversionStatusPreparing;
        NSNumber *last = self.downloadProgressSnapshot[taskId];
        CGFloat stable = last ? MAX(last.doubleValue, progress) : progress;
        self.downloadProgressSnapshot[taskId] = @(stable);
        task.downloadProgress = stable;
        progress = stable;
    }

    M3U8ConversionProgressBlock progressBlock = self.downloadProgressBlocks[taskId];
    if (progressBlock) {
        progressBlock(taskId, progress);
    }
    if ([self.delegate respondsToSelector:@selector(conversionService:didUpdateProgress:forTaskId:)]) {
        [self.delegate conversionService:self didUpdateProgress:progress forTaskId:taskId];
    }
}

- (void)URLSession:(NSURLSession *)session
      assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *taskId = assetDownloadTask.taskDescription;
    if (taskId.length == 0) {
        return;
    }

    M3U8ConversionTask *task = self.downloadTaskModels[taskId];
    M3U8ConversionProgressBlock progressBlock = self.downloadProgressBlocks[taskId];
    M3U8ConversionCompletionBlock completionBlock = self.downloadCompletionBlocks[taskId];

    [self.downloadTasks removeObjectForKey:taskId];
    [self.downloadProgressBlocks removeObjectForKey:taskId];
    [self.downloadCompletionBlocks removeObjectForKey:taskId];
    [self.downloadTaskModels removeObjectForKey:taskId];
    [self.downloadProgressSnapshot removeObjectForKey:taskId];

    if (!task) {
        if (completionBlock) {
            completionBlock(taskId, NO, [NSError errorWithDomain:@"M3U8ConverterError"
                                                           code:-1022
                                                       userInfo:@{
                NSLocalizedDescriptionKey: @"下载完成但任务已失效",
                NSLocalizedFailureReasonErrorKey: @"任务可能已被取消或在后台被清理。"
            }]);
        }
        return;
    }

    [self copyDownloadPackageIfNeededFromURL:location forTask:task];
    NSURL *packageURL = task.localPackageURL ?: location;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *prepareError = nil;
        NSURL *playlistURL = [self prepareLocalPlaylistForFFmpegFromPackage:packageURL
                                                                       task:task
                                                                      error:&prepareError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!playlistURL) {
                completionBlock(taskId, NO, prepareError ?: [NSError errorWithDomain:@"M3U8ConverterError"
                                                                                code:-1019
                                                                            userInfo:@{
                    NSLocalizedDescriptionKey: @"下载完成但无法准备本地播放列表",
                    NSLocalizedFailureReasonErrorKey: @"请稍后重试或更换链接。"
                }]);
                return;
            }

            task.localSourceURL = playlistURL;
            task.downloadProgress = 1.0;
            task.convertProgress = 0.0;
            if (task.status == M3U8ConversionStatusPaused) {
                NSLog(@"[转换服务] 下载完成，已暂停，等待手动继续");
                return;
            }
            task.status = M3U8ConversionStatusConverting;
            NSLog(@"[转换服务] 下载完成，使用FFmpeg进行本地转码");
            [self convertWithFFmpeg:task progress:progressBlock completion:completionBlock];
        });
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!error) {
        return;
    }
    NSString *taskId = task.taskDescription;
    if (taskId.length == 0) {
        return;
    }

    M3U8ConversionCompletionBlock completionBlock = self.downloadCompletionBlocks[taskId];
    [self.downloadTasks removeObjectForKey:taskId];
    [self.downloadProgressBlocks removeObjectForKey:taskId];
    [self.downloadCompletionBlocks removeObjectForKey:taskId];
    [self.downloadTaskModels removeObjectForKey:taskId];
    [self.downloadProgressSnapshot removeObjectForKey:taskId];

    if (completionBlock) {
        completionBlock(taskId, NO, error);
    }
}

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    NSString *method = challenge.protectionSpace.authenticationMethod;
    if ([method isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSString *host = challenge.protectionSpace.host.lowercaseString;
        if ([self.insecureTLSHosts containsObject:host]) {
            SecTrustRef trust = challenge.protectionSpace.serverTrust;
            if (trust) {
                NSURLCredential *credential = [NSURLCredential credentialForTrust:trust];
                completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
                return;
            }
        }
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)stopProgressMonitoringForTaskId:(NSString *)taskId {
    NSTimer *timer = self.progressTimers[taskId];
    if (timer) {
        [timer invalidate];
        [self.progressTimers removeObjectForKey:taskId];
    }
}

- (NSURL *)generateOutputURLForTask:(M3U8ConversionTask *)task {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentsURL = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *convertedDir = [documentsURL URLByAppendingPathComponent:@"Converted"];

    // 创建输出目录
    if (![fileManager fileExistsAtPath:convertedDir.path]) {
        [fileManager createDirectoryAtURL:convertedDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // 生成唯一文件名
    NSString *outputFileName = task.outputFileName;
    NSURL *outputURL = [convertedDir URLByAppendingPathComponent:outputFileName];

    // 如果文件已存在，添加时间戳
    if ([fileManager fileExistsAtPath:outputURL.path]) {
        NSString *baseName = [outputFileName stringByDeletingPathExtension];
        NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
        NSString *uniqueName = [NSString stringWithFormat:@"%@_%@.mp4", baseName, timestamp];
        outputURL = [convertedDir URLByAppendingPathComponent:uniqueName];
    }

    return outputURL;
}

- (void)copyDownloadPackageIfNeededFromURL:(NSURL *)location forTask:(M3U8ConversionTask *)task {
    M3U8FileManagerService *fileManager = [M3U8FileManagerService sharedService];
    NSURL *cacheDir = [fileManager sourceCacheDirectory];
    NSString *baseName = [[task fileName] stringByDeletingPathExtension];
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSString *folderName = [NSString stringWithFormat:@"%@_package_%ld", baseName, (long)timestamp];
    NSURL *destinationURL = [cacheDir URLByAppendingPathComponent:folderName];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:destinationURL error:nil];
    NSError *copyError = nil;
    if ([fm copyItemAtURL:location toURL:destinationURL error:&copyError]) {
        task.localPackageURL = destinationURL;
    } else {
        NSLog(@"[转换服务] 下载包复制失败: %@", copyError);
        task.localPackageURL = location;
    }
}

- (NSURL *)prepareLocalPlaylistForFFmpegFromPackage:(NSURL *)packageURL
                                                task:(M3U8ConversionTask *)task
                                               error:(NSError **)error {
    NSURL *playlistURL = [self findLocalPlaylistInPackage:packageURL];
    if (!playlistURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                         code:-1020
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"离线包未找到播放列表",
                NSLocalizedFailureReasonErrorKey: @"请检查下载是否完整。"
            }];
        }
        return nil;
    }

    NSString *content = [NSString stringWithContentsOfURL:playlistURL
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    if (content.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                         code:-1021
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"无法读取播放列表内容",
                NSLocalizedFailureReasonErrorKey: @"请稍后重试。"
            }];
        }
        return nil;
    }

    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *> *outputLines = [NSMutableArray arrayWithCapacity:lines.count];
    NSMutableArray<NSString *> *segmentLines = [NSMutableArray array];
    for (NSString *line in lines) {
        if (line.length > 0 && ![line hasPrefix:@"#"]) {
            [segmentLines addObject:line];
        }
    }
    BOOL needsRemap = NO;
    for (NSString *segment in segmentLines) {
        NSURL *segURL = [NSURL URLWithString:segment relativeToURL:playlistURL];
        if (![[NSFileManager defaultManager] fileExistsAtPath:segURL.path]) {
            needsRemap = YES;
            break;
        }
    }

    NSArray<NSURL *> *candidateFiles = [self collectSegmentFilesUnderDirectory:packageURL];
    NSMutableDictionary<NSString *, NSURL *> *fileNameMap = [NSMutableDictionary dictionary];
    if (candidateFiles.count == 0 && needsRemap) {
        if (error) {
            *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                         code:-1023
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"本地分片不足",
                NSLocalizedFailureReasonErrorKey: @"下载包中未找到可用分片文件。"
            }];
        }
        return nil;
    }
    for (NSURL *fileURL in candidateFiles) {
        if (fileURL.lastPathComponent.length > 0 && !fileNameMap[fileURL.lastPathComponent]) {
            fileNameMap[fileURL.lastPathComponent] = fileURL;
        }
    }

    NSURL *stagingDir = nil;
    if (needsRemap && candidateFiles.count > 0) {
        M3U8FileManagerService *fileManager = [M3U8FileManagerService sharedService];
        NSURL *cacheDir = [fileManager sourceCacheDirectory];
        NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
        NSString *dirName = [NSString stringWithFormat:@"ffmpeg_staging_%@_%ld", task.taskId, (long)timestamp];
        stagingDir = [cacheDir URLByAppendingPathComponent:dirName];
        [[NSFileManager defaultManager] createDirectoryAtURL:stagingDir
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:nil];
    }

    NSUInteger segmentIndex = 0;
    for (NSString *line in lines) {
        if ([line hasPrefix:@"#EXT-X-MAP"]) {
            NSString *rewritten = [self rewriteMapLine:line
                                           playlistURL:playlistURL
                                            packageURL:packageURL
                                           fileNameMap:fileNameMap];
            [outputLines addObject:rewritten ?: line];
            continue;
        }

        if ([line hasPrefix:@"#EXT-X-KEY"]) {
            NSError *keyError = nil;
            NSString *rewritten = [self rewriteKeyLine:line
                                           playlistURL:playlistURL
                                            packageURL:packageURL
                                           fileNameMap:fileNameMap
                                                 error:&keyError];
            if (!rewritten) {
                if (error) {
                    *error = keyError;
                }
                return nil;
            }
            [outputLines addObject:rewritten];
            continue;
        }

        if (line.length > 0 && ![line hasPrefix:@"#"]) {
            NSURL *segURL = nil;
            if (needsRemap && candidateFiles.count > 0 && segmentIndex < candidateFiles.count) {
                segURL = candidateFiles[segmentIndex];
            } else {
                NSString *name = [NSURL URLWithString:line].lastPathComponent;
                if (name.length > 0) {
                    name = [name stringByRemovingPercentEncoding] ?: name;
                }
                if (name.length > 0 && fileNameMap[name]) {
                    segURL = fileNameMap[name];
                } else {
                    NSURL *suffixMatch = [self findFileBySuffix:line underDirectory:packageURL];
                    if (suffixMatch) {
                        segURL = suffixMatch;
                    }
                }
                if (!segURL) {
                    segURL = [NSURL URLWithString:line relativeToURL:playlistURL];
                }
                BOOL exists = segURL.isFileURL ? [[NSFileManager defaultManager] fileExistsAtPath:segURL.path] : NO;
                if ((!exists || !segURL.isFileURL) && candidateFiles.count > 0 && segmentIndex < candidateFiles.count) {
                    segURL = candidateFiles[segmentIndex];
                }
            }

            NSString *path = segURL.path ?: line;
            if (stagingDir && segURL.isFileURL) {
                NSString *stagedName = [NSString stringWithFormat:@"seg_%05lu.frag", (unsigned long)segmentIndex];
                NSURL *stagedURL = [stagingDir URLByAppendingPathComponent:stagedName];
                if (![[NSFileManager defaultManager] fileExistsAtPath:stagedURL.path]) {
                    // Use copy to avoid any path/symlink resolution surprises.
                    [[NSFileManager defaultManager] copyItemAtURL:segURL toURL:stagedURL error:nil];
                }
                path = stagedURL.path;
            }
            NSString *fileURLString = [self fileURLStringForPath:path];
            [outputLines addObject:fileURLString ?: path];
            segmentIndex += 1;
        } else {
            [outputLines addObject:line];
        }
    }

    NSString *rewritten = [outputLines componentsJoinedByString:@"\n"];
    M3U8FileManagerService *fileManager = [M3U8FileManagerService sharedService];
    NSURL *cacheDir = stagingDir ?: [fileManager sourceCacheDirectory];
    NSString *baseName = task.taskId;
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSString *fileName = [NSString stringWithFormat:@"%@_ffmpeg_%ld.m3u8", baseName, (long)timestamp];
    NSURL *outURL = [cacheDir URLByAppendingPathComponent:fileName];
    NSError *writeError = nil;
    BOOL ok = [rewritten writeToURL:outURL atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (!ok) {
        if (error) {
            *error = writeError ?: [NSError errorWithDomain:@"M3U8ConverterError"
                                                       code:-1024
                                                   userInfo:@{
                NSLocalizedDescriptionKey: @"无法写入本地播放列表",
                NSLocalizedFailureReasonErrorKey: @"请检查存储空间或重试。"
            }];
        }
        return nil;
    }
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:outURL.path];
    if (!exists) {
        if (error) {
            *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                         code:-1025
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"播放列表写入后未找到文件",
                NSLocalizedFailureReasonErrorKey: @"请稍后重试。"
            }];
        }
        return nil;
    }
    return outURL;
}

- (NSURL *)findLocalPlaylistInPackage:(NSURL *)packageURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:packageURL
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:nil];
    NSURL *firstPlaylist = nil;
    for (NSURL *fileURL in enumerator) {
        if (![[fileURL pathExtension].lowercaseString isEqualToString:@"m3u8"]) {
            continue;
        }
        if (!firstPlaylist) {
            firstPlaylist = fileURL;
        }
        NSString *contents = [NSString stringWithContentsOfURL:fileURL
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil];
        if ([contents containsString:@"#EXTINF"]) {
            return fileURL;
        }
    }
    return firstPlaylist;
}

- (NSArray<NSURL *> *)collectSegmentFilesUnderDirectory:(NSURL *)directoryURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSSet<NSString *> *excludedExtensions = [NSSet setWithArray:@[@"m3u8", @"plist", @"json", @"txt", @"xml", @"html"]];
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:directoryURL
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:nil];
    for (NSURL *fileURL in enumerator) {
        NSNumber *isDirectory = nil;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) {
            continue;
        }
        NSString *ext = fileURL.pathExtension.lowercaseString;
        if ([excludedExtensions containsObject:ext]) {
            continue;
        }
        NSString *name = fileURL.lastPathComponent.lowercaseString;
        if ([name isEqualToString:@"info.plist"]) {
            continue;
        }
        if (ext.length == 0 || ext.length <= 4) {
            [files addObject:fileURL];
        }
    }
    [files sortUsingComparator:^NSComparisonResult(NSURL * _Nonnull a, NSURL * _Nonnull b) {
        return [a.lastPathComponent compare:b.lastPathComponent];
    }];
    return files;
}

- (NSString *)rewriteMapLine:(NSString *)mapLine
                 playlistURL:(NSURL *)playlistURL
                  packageURL:(NSURL *)packageURL
                  fileNameMap:(NSDictionary<NSString *, NSURL *> *)fileNameMap {
    NSRange uriRange = [mapLine rangeOfString:@"URI="];
    if (uriRange.location == NSNotFound) {
        return mapLine;
    }
    NSUInteger start = uriRange.location + uriRange.length;
    NSString *tail = [mapLine substringFromIndex:start];
    NSString *uri = nil;
    if ([tail hasPrefix:@"\""]) {
        NSString *rest = [tail substringFromIndex:1];
        NSRange endRange = [rest rangeOfString:@"\""];
        if (endRange.location != NSNotFound) {
            uri = [rest substringToIndex:endRange.location];
        }
    } else {
        NSRange endRange = [tail rangeOfString:@","];
        if (endRange.location == NSNotFound) {
            uri = tail;
        } else {
            uri = [tail substringToIndex:endRange.location];
        }
    }
    if (uri.length == 0) {
        return mapLine;
    }

    NSString *decodedURI = [uri stringByRemovingPercentEncoding] ?: uri;
    NSURL *mapURL = [NSURL URLWithString:decodedURI relativeToURL:playlistURL];
    NSURL *resolved = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:mapURL.path]) {
        resolved = mapURL;
    }

    if (!resolved) {
        NSString *fileName = mapURL.lastPathComponent;
        if (fileName.length > 0) {
            fileName = [fileName stringByRemovingPercentEncoding] ?: fileName;
        }
        resolved = fileNameMap[fileName] ?: [self findFileNamed:fileName underDirectory:packageURL];
    }

    if (!resolved) {
        resolved = [self findFileBySuffix:decodedURI underDirectory:packageURL];
    }

    if (!resolved) {
        resolved = [self findFirstFileWithExtension:@"cmfv" underDirectory:packageURL] ?: mapURL;
    }

    NSString *fileURLString = [self fileURLStringForPath:resolved.path ?: uri];
    return [mapLine stringByReplacingOccurrencesOfString:uri withString:fileURLString ?: uri];
}

- (NSString *)rewriteKeyLine:(NSString *)keyLine
                 playlistURL:(NSURL *)playlistURL
                  packageURL:(NSURL *)packageURL
                 fileNameMap:(NSDictionary<NSString *, NSURL *> *)fileNameMap
                       error:(NSError **)error {
    NSString *method = [self attributeValueForKey:@"METHOD" inTagLine:keyLine];
    if (method.length == 0) {
        return keyLine;
    }

    if ([method isEqualToString:@"NONE"]) {
        return keyLine;
    }

    if (![method isEqualToString:@"AES-128"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                         code:-1022
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"检测到加密HLS",
                NSLocalizedFailureReasonErrorKey: @"当前仅支持AES-128离线转码，SAMPLE-AES或DRM内容不支持。"
            }];
        }
        return nil;
    }

    NSString *uri = [self attributeValueForKey:@"URI" inTagLine:keyLine];
    if (uri.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                         code:-1026
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"加密HLS缺少密钥URI",
                NSLocalizedFailureReasonErrorKey: @"请检查播放列表内容或更换链接。"
            }];
        }
        return nil;
    }

    NSString *decodedURI = [uri stringByRemovingPercentEncoding] ?: uri;
    NSURL *keyURL = [NSURL URLWithString:decodedURI relativeToURL:playlistURL];
    NSURL *resolved = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:keyURL.path]) {
        resolved = keyURL;
    }

    if (!resolved) {
        NSString *fileName = keyURL.lastPathComponent;
        if (fileName.length > 0) {
            fileName = [fileName stringByRemovingPercentEncoding] ?: fileName;
        }
        resolved = fileNameMap[fileName] ?: [self findFileNamed:fileName underDirectory:packageURL];
    }

    if (!resolved) {
        resolved = [self findFileBySuffix:decodedURI underDirectory:packageURL];
    }

    if (!resolved) {
        NSString *scheme = keyURL.scheme.lowercaseString;
        if ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) {
            if (![M3U8FFmpegService isHTTPSProtocolAvailable]) {
                NSURL *cachedKeyURL = [self downloadKeyToLocalCache:keyURL];
                if (cachedKeyURL) {
                    NSString *fileURLString = [self fileURLStringForPath:cachedKeyURL.path];
                    return [keyLine stringByReplacingOccurrencesOfString:uri withString:fileURLString ?: uri];
                }
                if (error) {
                    *error = [NSError errorWithDomain:@"M3U8ConverterError"
                                                 code:-1027
                                             userInfo:@{
                        NSLocalizedDescriptionKey: @"FFmpeg不支持HTTPS密钥",
                        NSLocalizedFailureReasonErrorKey: @"当前FFmpeg构建未启用HTTPS，且未能下载密钥到本地。"
                    }];
                }
                return nil;
            }
        }
        return keyLine;
    }

    NSString *fileURLString = [self fileURLStringForPath:resolved.path ?: uri];
    return [keyLine stringByReplacingOccurrencesOfString:uri withString:fileURLString ?: uri];
}

- (NSString *)attributeValueForKey:(NSString *)key inTagLine:(NSString *)line {
    if (key.length == 0 || line.length == 0) {
        return nil;
    }
    NSString *pattern = [NSString stringWithFormat:@"%@=", key];
    NSRange range = [line rangeOfString:pattern];
    if (range.location == NSNotFound) {
        return nil;
    }
    NSUInteger start = range.location + range.length;
    if (start >= line.length) {
        return nil;
    }
    NSString *tail = [line substringFromIndex:start];
    if ([tail hasPrefix:@"\""]) {
        NSString *rest = [tail substringFromIndex:1];
        NSRange endRange = [rest rangeOfString:@"\""];
        if (endRange.location != NSNotFound) {
            return [rest substringToIndex:endRange.location];
        }
        return nil;
    }
    NSRange endRange = [tail rangeOfString:@","];
    if (endRange.location == NSNotFound) {
        return tail;
    }
    return [tail substringToIndex:endRange.location];
}

- (NSURL *)downloadKeyToLocalCache:(NSURL *)keyURL {
    if (!keyURL) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:keyURL];
    if (data.length == 0) {
        return nil;
    }
    M3U8FileManagerService *fileManager = [M3U8FileManagerService sharedService];
    NSURL *cacheDir = [fileManager sourceCacheDirectory];
    NSString *fileName = keyURL.lastPathComponent.length > 0 ? keyURL.lastPathComponent : @"key";
    NSString *baseName = [fileName stringByDeletingPathExtension];
    NSString *ext = [fileName pathExtension];
    if (ext.length == 0) {
        ext = @"key";
    }
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSString *uniqueName = [NSString stringWithFormat:@"%@_%ld.%@", baseName, (long)timestamp, ext];
    NSURL *outURL = [cacheDir URLByAppendingPathComponent:uniqueName];
    if ([data writeToURL:outURL atomically:YES]) {
        return outURL;
    }
    return nil;
}

- (NSString *)fileURLStringForPath:(NSString *)path {
    if (path.length == 0) {
        return nil;
    }
    // If path is already in staging, keep it as-is.
    if ([path containsString:@"/ffmpeg_staging_"]) {
        NSURL *url = [NSURL fileURLWithPath:path];
        return url.absoluteString;
    }
    NSString *resolved = [path stringByResolvingSymlinksInPath];
    if ([resolved hasPrefix:@"/private/var/"]) {
        NSString *alt = [resolved stringByReplacingOccurrencesOfString:@"/private/var/" withString:@"/var/"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:alt]) {
            resolved = alt;
        }
    }
    NSURL *url = [NSURL fileURLWithPath:resolved];
    return url.absoluteString;
}

- (NSURL *)findFileNamed:(NSString *)fileName underDirectory:(NSURL *)directoryURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:directoryURL
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:nil];
    for (NSURL *fileURL in enumerator) {
        if ([fileURL.lastPathComponent isEqualToString:fileName]) {
            return fileURL;
        }
    }
    return nil;
}

- (NSURL *)findFileBySuffix:(NSString *)suffix underDirectory:(NSURL *)directoryURL {
    if (suffix.length == 0) {
        return nil;
    }
    NSString *normalized = [suffix stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    normalized = [normalized stringByRemovingPercentEncoding] ?: normalized;
    if ([normalized hasPrefix:@"file://"]) {
        NSURL *url = [NSURL URLWithString:normalized];
        normalized = url.path ?: normalized;
    }
    if ([normalized hasPrefix:@"/"]) {
        normalized = [normalized substringFromIndex:1];
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:directoryURL
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:nil];
    for (NSURL *fileURL in enumerator) {
        NSString *path = fileURL.path;
        if ([path hasSuffix:normalized]) {
            return fileURL;
        }
    }
    return nil;
}

- (NSURL *)findFirstFileWithExtension:(NSString *)extension underDirectory:(NSURL *)directoryURL {
    if (extension.length == 0) {
        return nil;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:directoryURL
                                                   includingPropertiesForKeys:nil
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:nil];
    NSString *targetExt = extension.lowercaseString;
    for (NSURL *fileURL in enumerator) {
        if ([fileURL.pathExtension.lowercaseString isEqualToString:targetExt]) {
            return fileURL;
        }
    }
    return nil;
}

- (void)cleanLocalSourceIfNeededForTask:(M3U8ConversionTask *)task {
    M3U8FileManagerService *fileManager = [M3U8FileManagerService sharedService];
    if (task.localPackageURL) {
        [fileManager deleteFileAtURL:task.localPackageURL error:nil];
        task.localPackageURL = nil;
    } else if (task.localSourceURL) {
        [fileManager deleteFileAtURL:task.localSourceURL error:nil];
    }
    task.localSourceURL = nil;
}

- (void)cleanupTempPlaylistIfNeededForTask:(M3U8ConversionTask *)task {
    if (!task.localSourceURL) {
        return;
    }
    NSString *name = task.localSourceURL.lastPathComponent;
    if ([name containsString:@"_ffmpeg_"] && [name hasSuffix:@".m3u8"]) {
        M3U8FileManagerService *fileManager = [M3U8FileManagerService sharedService];
        [fileManager deleteFileAtURL:task.localSourceURL error:nil];
    }
}

@end
