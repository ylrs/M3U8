//
//  M3U8FileManagerService.m
//  M3U8Converter
//

#import "M3U8FileManagerService.h"

static NSString * const kAppGroupID = @"group.com.m3u8converter.shared";
static NSString * const kSourceCachePath = @"Cache/Sources";
static NSString * const kConvertedPath = @"Converted";

@interface M3U8FileManagerService ()

@property (nonatomic, strong) NSFileManager *fileManager;

@end

@implementation M3U8FileManagerService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static M3U8FileManagerService *instance = nil;
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
        _fileManager = [NSFileManager defaultManager];
        [self createDirectoriesIfNeeded];
    }
    return self;
}

#pragma mark - Public Methods

- (NSURL *)sourceCacheDirectory {
    NSURL *documentsURL = [self documentsDirectory];
    NSURL *cacheDir = [documentsURL URLByAppendingPathComponent:kSourceCachePath];
    [self createDirectoryIfNeededAtURL:cacheDir];
    return cacheDir;
}

- (NSURL *)convertedDirectory {
    NSURL *documentsURL = [self documentsDirectory];
    NSURL *convertedDir = [documentsURL URLByAppendingPathComponent:kConvertedPath];
    [self createDirectoryIfNeededAtURL:convertedDir];
    return convertedDir;
}

- (nullable NSURL *)sharedContainerDirectory {
    NSURL *containerURL = [self.fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroupID];
    if (containerURL) {
        [self createDirectoryIfNeededAtURL:containerURL];
    }
    return containerURL;
}

- (nullable NSURL *)copyFileToCache:(NSURL *)sourceURL error:(NSError *__autoreleasing  _Nullable *)error {
    NSURL *cacheDir = [self sourceCacheDirectory];
    NSString *uniqueName = [self uniqueFileNameFromOriginal:sourceURL.lastPathComponent];
    NSURL *destinationURL = [cacheDir URLByAppendingPathComponent:uniqueName];

    BOOL success = [self.fileManager copyItemAtURL:sourceURL toURL:destinationURL error:error];
    return success ? destinationURL : nil;
}

- (void)cleanExpiredCacheWithDays:(NSInteger)days {
    NSURL *cacheDir = [self sourceCacheDirectory];
    NSArray *files = [self.fileManager contentsOfDirectoryAtURL:cacheDir
                                      includingPropertiesForKeys:@[NSURLCreationDateKey]
                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                           error:nil];

    NSDate *expirationDate = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay
                                                                       value:-days
                                                                      toDate:[NSDate date]
                                                                     options:0];

    for (NSURL *fileURL in files) {
        NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:fileURL.path error:nil];
        NSDate *creationDate = attributes[NSFileCreationDate];

        if (creationDate && [creationDate compare:expirationDate] == NSOrderedAscending) {
            [self.fileManager removeItemAtURL:fileURL error:nil];
        }
    }
}

- (BOOL)clearSourceCacheWithError:(NSError *__autoreleasing  _Nullable *)error {
    NSURL *cacheDir = [self sourceCacheDirectory];
    NSArray<NSURL *> *items = [self.fileManager contentsOfDirectoryAtURL:cacheDir
                                              includingPropertiesForKeys:nil
                                                                 options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                   error:error];
    if (!items) {
        return NO;
    }
    BOOL success = YES;
    for (NSURL *item in items) {
        if (![self.fileManager removeItemAtURL:item error:error]) {
            success = NO;
        }
    }
    return success;
}

- (long long)fileSizeAtURL:(NSURL *)fileURL {
    NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:fileURL.path error:nil];
    return [attributes[NSFileSize] longLongValue];
}

- (BOOL)fileExistsAtURL:(NSURL *)fileURL {
    return [self.fileManager fileExistsAtPath:fileURL.path];
}

- (BOOL)deleteFileAtURL:(NSURL *)fileURL error:(NSError *__autoreleasing  _Nullable *)error {
    return [self.fileManager removeItemAtURL:fileURL error:error];
}

- (NSString *)uniqueFileNameFromOriginal:(NSString *)originalName {
    NSString *baseName = [originalName stringByDeletingPathExtension];
    NSString *ext = [originalName pathExtension];
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];

    return [NSString stringWithFormat:@"%@_%ld.%@", baseName, (long)timestamp, ext];
}

#pragma mark - Private Methods

- (NSURL *)documentsDirectory {
    return [[self.fileManager URLsForDirectory:NSDocumentDirectory
                                     inDomains:NSUserDomainMask] firstObject];
}

- (void)createDirectoriesIfNeeded {
    [self sourceCacheDirectory];
    [self convertedDirectory];
}

- (void)createDirectoryIfNeededAtURL:(NSURL *)url {
    if (![self.fileManager fileExistsAtPath:url.path]) {
        [self.fileManager createDirectoryAtURL:url
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:nil];
    }
}

@end
