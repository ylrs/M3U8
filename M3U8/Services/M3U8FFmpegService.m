//
//  M3U8FFmpegService.m
//  M3U8Converter
//

#import "M3U8FFmpegService.h"

// 检查是否有 FFmpegKit 可用
#if __has_include(<ffmpegkit/FFmpegKit.h>)
#import <ffmpegkit/FFmpegKit.h>
#import <ffmpegkit/FFmpegKitConfig.h>
#import <ffmpegkit/FFmpegSession.h>
#import <ffmpegkit/ReturnCode.h>
#import <ffmpegkit/Statistics.h>
#define FFMPEG_AVAILABLE 1
#else
#define FFMPEG_AVAILABLE 0
#endif

@interface M3U8FFmpegService ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *activeSessions;
@property (nonatomic, strong) dispatch_queue_t conversionQueue;

@end

@implementation M3U8FFmpegService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static M3U8FFmpegService *instance = nil;
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
        _activeSessions = [NSMutableDictionary dictionary];
        _conversionQueue = dispatch_queue_create("com.m3u8converter.ffmpeg", DISPATCH_QUEUE_CONCURRENT);
        _defaultQuality = M3U8VideoQualityHigh;  // 默认高质量
    }
    return self;
}

#pragma mark - Public Methods

+ (BOOL)isFFmpegAvailable {
#if FFMPEG_AVAILABLE
    return YES;
#else
    return NO;
#endif
}

+ (NSString *)ffmpegVersion {
#if FFMPEG_AVAILABLE
    return [FFmpegKitConfig getFFmpegVersion];
#else
    return @"FFmpeg not available";
#endif
}

+ (BOOL)isHTTPSProtocolAvailable {
#if FFMPEG_AVAILABLE
    static dispatch_once_t onceToken;
    static BOOL httpsSupported = NO;
    dispatch_once(&onceToken, ^{
        FFmpegSession *session = [FFmpegKit execute:@"-protocols"];
        NSString *output = [[session getOutput] lowercaseString] ?: @"";
        httpsSupported = [output containsString:@"https"];
        NSLog(@"[FFmpeg服务] HTTPS协议支持: %@", httpsSupported ? @"YES" : @"NO");
    });
    return httpsSupported;
#else
    return NO;
#endif
}

- (void)convertM3U8ToMP4WithTask:(M3U8ConversionTask *)task
                         quality:(M3U8VideoQuality)quality
                        progress:(M3U8FFmpegProgressBlock)progressBlock
                      completion:(M3U8FFmpegCompletionBlock)completionBlock {

#if !FFMPEG_AVAILABLE
    NSError *error = [NSError errorWithDomain:@"M3U8FFmpegError"
                                         code:-2001
                                     userInfo:@{NSLocalizedDescriptionKey: @"FFmpeg framework not installed"}];
    dispatch_async(dispatch_get_main_queue(), ^{
        completionBlock(task.taskId, NO, error);
    });
    return;
#else

    NSURL *inputURL = task.localSourceURL ?: task.sourceURL;
    NSLog(@"[FFmpeg服务] 开始转换任务 %@", task.taskId);
    NSLog(@"[FFmpeg服务] 源URL: %@", inputURL);
    NSLog(@"[FFmpeg服务] 质量级别: %ld", (long)quality);

    dispatch_async(self.conversionQueue, ^{
        if (!inputURL) {
            NSError *error = [NSError errorWithDomain:@"M3U8FFmpegError"
                                                 code:-2003
                                             userInfo:@{
                NSLocalizedDescriptionKey: @"源文件为空",
                NSLocalizedFailureReasonErrorKey: @"未找到可用的源URL，无法开始转换。"
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(task.taskId, NO, error);
            });
            return;
        }
        if ([inputURL.scheme.lowercaseString isEqualToString:@"https"] &&
            ![M3U8FFmpegService isHTTPSProtocolAvailable]) {
            NSError *error = [NSError errorWithDomain:@"M3U8FFmpegError"
                                                 code:-2002
                                             userInfo:@{
                NSLocalizedDescriptionKey: @"FFmpeg不支持HTTPS协议",
                NSLocalizedFailureReasonErrorKey: @"当前FFmpeg构建未启用HTTPS（openssl/gnutls/securetransport）。\n\n请使用支持HTTPS的ffmpeg-kit版本（例如 full/full-gpl）。"
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(task.taskId, NO, error);
            });
            return;
        }

        // 生成输出文件路径
        NSURL *outputURL = [self generateOutputURLForTask:task];
        NSLog(@"[FFmpeg服务] 输出URL: %@", outputURL);

        // 构建FFmpeg命令
        NSString *sourceArg = inputURL.isFileURL ? inputURL.path : inputURL.absoluteString;
        NSString *command = [self buildFFmpegCommandForSource:sourceArg
                                                       output:outputURL.path
                                                      quality:quality];

        NSLog(@"[FFmpeg服务] FFmpeg 命令: ffmpeg %@", command);

        // 执行FFmpeg命令
        FFmpegSession *session = [FFmpegKit executeAsync:command
                                         withCompleteCallback:^(FFmpegSession *session) {
            ReturnCode *returnCode = [session getReturnCode];

            if ([ReturnCode isSuccess:returnCode]) {
                NSLog(@"[FFmpeg服务] 转换成功！");
                task.outputURL = outputURL;
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(task.taskId, YES, nil);
                });
            } else {
                NSLog(@"[FFmpeg服务] 转换失败");
                NSLog(@"[FFmpeg服务] 输出: %@", [session getOutput]);
                NSLog(@"[FFmpeg服务] 错误: %@", [session getFailStackTrace]);

                NSError *error = [NSError errorWithDomain:@"M3U8FFmpegError"
                                                     code:[returnCode getValue]
                                                 userInfo:@{
                    NSLocalizedDescriptionKey: @"FFmpeg conversion failed",
                    NSLocalizedFailureReasonErrorKey: [session getOutput] ?: @"Unknown error"
                }];

                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(task.taskId, NO, error);
                });
            }

            // 移除会话
            [self.activeSessions removeObjectForKey:task.taskId];
        }
                                             withLogCallback:^(Log *log) {
            NSString *message = [log getMessage] ?: @"";
            NSString *lower = message.lowercaseString;
            if ([lower containsString:@"error"] ||
                [lower containsString:@"failed"] ||
                [lower containsString:@"invalid"] ||
                [lower containsString:@"unable to open"]) {
                NSLog(@"[FFmpeg Log] %@", message);
            }
        }
                                      withStatisticsCallback:^(Statistics *statistics) {
            // 计算进度
            int time = [statistics getTime];
            if (time > 0 && task.duration > 0) {
                CGFloat progress = (CGFloat)time / (task.duration * 1000.0);
                progress = MIN(MAX(progress, 0.0), 1.0);

                dispatch_async(dispatch_get_main_queue(), ^{
                    progressBlock(task.taskId, progress);
                });
            }
        }];

        // 保存会话以便取消
        self.activeSessions[task.taskId] = session;
    });
#endif
}

- (void)cancelConversionForTaskId:(NSString *)taskId {
#if FFMPEG_AVAILABLE
    FFmpegSession *session = self.activeSessions[taskId];
    if (session) {
        NSLog(@"[FFmpeg服务] 取消任务 %@", taskId);
        [FFmpegKit cancel:session.getSessionId];
        [self.activeSessions removeObjectForKey:taskId];
    }
#endif
}

#pragma mark - Private Methods

- (NSString *)buildFFmpegCommandForSource:(NSString *)sourceURL
                                   output:(NSString *)outputPath
                                  quality:(M3U8VideoQuality)quality {

    // CRF 值 (Constant Rate Factor): 值越小质量越高
    // 0 = 无损, 18 = 视觉上无损, 23 = 默认, 28 = 低质量
    NSInteger crf = 23;  // 默认值
    NSString *preset = @"medium";  // 编码速度: ultrafast, fast, medium, slow, veryslow

    switch (quality) {
        case M3U8VideoQualityLow:
            crf = 28;
            preset = @"fast";
            break;
        case M3U8VideoQualityMedium:
            crf = 23;
            preset = @"medium";
            break;
        case M3U8VideoQualityHigh:
            crf = 20;
            preset = @"slow";
            break;
        case M3U8VideoQualityVeryHigh:
            crf = 18;
            preset = @"slow";
            break;
        case M3U8VideoQualityLossless:
            crf = 0;
            preset = @"veryslow";
            break;
    }

    // 构建命令
    // -i: 输入文件
    // -c:v libx264: 使用H.264编码器
    // -preset: 编码速度预设
    // -crf: 质量因子
    // -c:a aac: 音频使用AAC编码
    // -b:a 192k: 音频比特率
    // -movflags +faststart: 优化MP4用于流式播放
    // -y: 覆盖输出文件

    NSString *command = [NSString stringWithFormat:
        @"-protocol_whitelist file,crypto,concat,subfile "
        @"-allowed_extensions ALL "
        @"-i \"%@\" "
        @"-c:v h264_videotoolbox -b:v 3000k "
        @"-preset %@ "
        @"-crf %ld "
        @"-c:a aac "
        @"-b:a 192k "
        @"-movflags +faststart "
        @"-y "
        @"\"%@\"",
        sourceURL,
        preset,
        (long)crf,
        outputPath
    ];

    return command;
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

@end
