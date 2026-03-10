//
//  M3U8FFmpegService.h
//  M3U8Converter
//
//  FFmpeg 转换服务 - 支持所有视频格式
//

#import <Foundation/Foundation.h>
#import "M3U8ConversionTask.h"

NS_ASSUME_NONNULL_BEGIN

@class M3U8FFmpegService;

// 转换进度回调
typedef void(^M3U8FFmpegProgressBlock)(NSString *taskId, CGFloat progress);

// 转换完成回调
typedef void(^M3U8FFmpegCompletionBlock)(NSString *taskId, BOOL success, NSError * _Nullable error);

// 视频质量级别
typedef NS_ENUM(NSInteger, M3U8VideoQuality) {
    M3U8VideoQualityLow = 0,      // 低质量 (CRF 28)
    M3U8VideoQualityMedium,       // 中等质量 (CRF 23)
    M3U8VideoQualityHigh,         // 高质量 (CRF 20)
    M3U8VideoQualityVeryHigh,     // 超高质量 (CRF 18)
    M3U8VideoQualityLossless      // 无损质量 (CRF 0)
};

@interface M3U8FFmpegService : NSObject

@property (nonatomic, assign) M3U8VideoQuality defaultQuality;  // 默认: 高质量

+ (instancetype)sharedService;

/**
 * 使用FFmpeg转换M3U8到MP4
 */
- (void)convertM3U8ToMP4WithTask:(M3U8ConversionTask *)task
                         quality:(M3U8VideoQuality)quality
                        progress:(M3U8FFmpegProgressBlock)progressBlock
                      completion:(M3U8FFmpegCompletionBlock)completionBlock;

/**
 * 取消转换任务
 */
- (void)cancelConversionForTaskId:(NSString *)taskId;

/**
 * 检查FFmpeg是否可用
 */
+ (BOOL)isFFmpegAvailable;

/**
 * 检查FFmpeg是否支持HTTPS协议
 */
+ (BOOL)isHTTPSProtocolAvailable;

/**
 * 获取FFmpeg版本信息
 */
+ (NSString *)ffmpegVersion;

@end

NS_ASSUME_NONNULL_END
