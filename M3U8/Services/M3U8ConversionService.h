//
//  M3U8ConversionService.h
//  M3U8Converter
//
//  核心转换服务（使用 AVFoundation）
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "M3U8ConversionTask.h"

NS_ASSUME_NONNULL_BEGIN

@class M3U8ConversionService;

// 转换进度回调
typedef void(^M3U8ConversionProgressBlock)(NSString *taskId, CGFloat progress);

// 转换完成回调
typedef void(^M3U8ConversionCompletionBlock)(NSString *taskId, BOOL success, NSError * _Nullable error);

@protocol M3U8ConversionServiceDelegate <NSObject>
@optional
- (void)conversionService:(M3U8ConversionService *)service
         didUpdateProgress:(CGFloat)progress
                 forTaskId:(NSString *)taskId;

- (void)conversionService:(M3U8ConversionService *)service
    didCompleteConversionForTaskId:(NSString *)taskId
                         outputURL:(NSURL *)outputURL;

- (void)conversionService:(M3U8ConversionService *)service
    didFailConversionForTaskId:(NSString *)taskId
                         error:(NSError *)error;
@end

@interface M3U8ConversionService : NSObject

@property (nonatomic, weak, nullable) id<M3U8ConversionServiceDelegate> delegate;
@property (nonatomic, assign, readonly) NSInteger maxConcurrentTasks;

+ (instancetype)sharedService;

/**
 * 开始转换任务
 */
- (void)startConversionForTask:(M3U8ConversionTask *)task
                      progress:(M3U8ConversionProgressBlock)progressBlock
                    completion:(M3U8ConversionCompletionBlock)completionBlock;

/**
 * 取消转换任务
 */
- (void)cancelConversionForTaskId:(NSString *)taskId;

/**
 * 取消所有任务
 */
- (void)cancelAllConversions;

/**
 * 验证 M3U8 源是否可用
 */
- (void)validateM3U8Source:(NSURL *)sourceURL
                completion:(void(^)(BOOL isValid, NSError * _Nullable error))completion;

/**
 * 获取正在进行的任务数量
 */
- (NSInteger)activeTasksCount;

@end

NS_ASSUME_NONNULL_END
