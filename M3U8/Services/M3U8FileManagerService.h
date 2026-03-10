//
//  M3U8FileManagerService.h
//  M3U8Converter
//
//  文件管理服务
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface M3U8FileManagerService : NSObject

+ (instancetype)sharedService;

/**
 * 获取源文件缓存目录
 */
- (NSURL *)sourceCacheDirectory;

/**
 * 获取转换输出目录
 */
- (NSURL *)convertedDirectory;

/**
 * 获取 App Group 共享容器目录
 */
- (nullable NSURL *)sharedContainerDirectory;

/**
 * 复制文件到缓存目录
 */
- (nullable NSURL *)copyFileToCache:(NSURL *)sourceURL error:(NSError **)error;

/**
 * 清理过期缓存
 */
- (void)cleanExpiredCacheWithDays:(NSInteger)days;

/**
 * 获取文件大小
 */
- (long long)fileSizeAtURL:(NSURL *)fileURL;

/**
 * 检查文件是否存在
 */
- (BOOL)fileExistsAtURL:(NSURL *)fileURL;

/**
 * 删除文件
 */
- (BOOL)deleteFileAtURL:(NSURL *)fileURL error:(NSError **)error;

/**
 * 生成唯一文件名
 */
- (NSString *)uniqueFileNameFromOriginal:(NSString *)originalName;

@end

NS_ASSUME_NONNULL_END
