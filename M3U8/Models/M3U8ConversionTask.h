//
//  M3U8ConversionTask.h
//  M3U8Converter
//
//  转换任务模型
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 转换状态枚举
typedef NS_ENUM(NSInteger, M3U8ConversionStatus) {
    M3U8ConversionStatusPending = 0,      // 等待中
    M3U8ConversionStatusPreparing,        // 准备中
    M3U8ConversionStatusConverting,       // 转换中
    M3U8ConversionStatusPaused,           // 已暂停
    M3U8ConversionStatusCompleted,        // 已完成
    M3U8ConversionStatusFailed,           // 失败
    M3U8ConversionStatusCancelled         // 已取消
};

// 输入源类型枚举
typedef NS_ENUM(NSInteger, M3U8InputSourceType) {
    M3U8InputSourceTypeLocalFile = 0,     // 本地文件
    M3U8InputSourceTypeRemoteURL,         // 网络 URL
    M3U8InputSourceTypeSharedFile         // 分享的文件
};

@interface M3U8ConversionTask : NSObject <NSCoding, NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *taskId;
@property (nonatomic, strong) NSURL *sourceURL;
@property (nonatomic, strong, nullable) NSURL *outputURL;
@property (nonatomic, assign) M3U8InputSourceType sourceType;
@property (nonatomic, assign) M3U8ConversionStatus status;
@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, assign) CGFloat downloadProgress;
@property (nonatomic, assign) CGFloat convertProgress;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *completedAt;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, assign) long long fileSize;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong, nullable) NSURL *localSourceURL;
@property (nonatomic, strong, nullable) NSURL *localPackageURL;
@property (nonatomic, copy, nullable) NSString *customTitle;

- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                       sourceType:(M3U8InputSourceType)sourceType;

- (NSString *)fileName;
- (NSString *)outputFileName;
- (NSString *)safeFileBaseName;
- (NSString *)statusDisplayName;
- (BOOL)isActive;
- (BOOL)isFinished;

@end

NS_ASSUME_NONNULL_END
