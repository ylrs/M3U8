//
//  M3U8ConversionTask.m
//  M3U8Converter
//

#import "M3U8ConversionTask.h"

@implementation M3U8ConversionTask

- (instancetype)initWithSourceURL:(NSURL *)sourceURL sourceType:(M3U8InputSourceType)sourceType {
    self = [super init];
    if (self) {
        _taskId = [[NSUUID UUID] UUIDString];
        _sourceURL = sourceURL;
        _sourceType = sourceType;
        _status = M3U8ConversionStatusPending;
        _progress = 0.0;
        _createdAt = [NSDate date];
        _fileSize = 0;
        _duration = 0;
    }
    return self;
}

#pragma mark - Public Methods

- (NSString *)fileName {
    if (self.customTitle.length > 0) {
        return self.customTitle;
    }
    NSString *name = self.sourceURL.lastPathComponent;
    if (name.length == 0) {
        return self.taskId ?: @"output";
    }
    return name;
}

- (NSString *)outputFileName {
    if (self.customTitle.length > 0) {
        NSString *baseName = [self safeFileBaseNameFromTitle:self.customTitle];
        return [NSString stringWithFormat:@"%@.mp4", baseName];
    }
    NSString *fileName = [self fileName];
    NSString *baseName = [fileName stringByDeletingPathExtension];
    return [NSString stringWithFormat:@"%@.mp4", baseName];
}

- (NSString *)safeFileBaseName {
    if (self.customTitle.length > 0) {
        return [self safeFileBaseNameFromTitle:self.customTitle];
    }
    NSString *baseName = [[self fileName] stringByDeletingPathExtension];
    return [self safeFileBaseNameFromTitle:baseName];
}

- (NSString *)statusDisplayName {
    switch (self.status) {
        case M3U8ConversionStatusPending:
            return @"等待中";
        case M3U8ConversionStatusPreparing:
            return @"准备中";
        case M3U8ConversionStatusConverting:
            return @"转换中";
        case M3U8ConversionStatusPaused:
            return @"已暂停";
        case M3U8ConversionStatusCompleted:
            return @"已完成";
        case M3U8ConversionStatusFailed:
            return @"失败";
        case M3U8ConversionStatusCancelled:
            return @"已取消";
    }
}

- (BOOL)isActive {
    return self.status == M3U8ConversionStatusPreparing ||
           self.status == M3U8ConversionStatusConverting;
}

- (BOOL)isFinished {
    return self.status == M3U8ConversionStatusCompleted ||
           self.status == M3U8ConversionStatusFailed ||
           self.status == M3U8ConversionStatusCancelled;
}

#pragma mark - NSCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.taskId forKey:@"taskId"];
    [coder encodeObject:self.sourceURL forKey:@"sourceURL"];
    [coder encodeObject:self.outputURL forKey:@"outputURL"];
    [coder encodeObject:self.localSourceURL forKey:@"localSourceURL"];
    [coder encodeObject:self.localPackageURL forKey:@"localPackageURL"];
    [coder encodeInteger:self.sourceType forKey:@"sourceType"];
    [coder encodeInteger:self.status forKey:@"status"];
    [coder encodeDouble:self.progress forKey:@"progress"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
    [coder encodeObject:self.completedAt forKey:@"completedAt"];
    [coder encodeObject:self.errorMessage forKey:@"errorMessage"];
    [coder encodeInt64:self.fileSize forKey:@"fileSize"];
    [coder encodeDouble:self.duration forKey:@"duration"];
    [coder encodeObject:self.customTitle forKey:@"customTitle"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _taskId = [coder decodeObjectOfClass:[NSString class] forKey:@"taskId"];
        _sourceURL = [coder decodeObjectOfClass:[NSURL class] forKey:@"sourceURL"];
        _outputURL = [coder decodeObjectOfClass:[NSURL class] forKey:@"outputURL"];
        _localSourceURL = [coder decodeObjectOfClass:[NSURL class] forKey:@"localSourceURL"];
        _localPackageURL = [coder decodeObjectOfClass:[NSURL class] forKey:@"localPackageURL"];
        _sourceType = [coder decodeIntegerForKey:@"sourceType"];
        _status = [coder decodeIntegerForKey:@"status"];
        _progress = [coder decodeDoubleForKey:@"progress"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        _completedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"completedAt"];
        _errorMessage = [coder decodeObjectOfClass:[NSString class] forKey:@"errorMessage"];
        _fileSize = [coder decodeInt64ForKey:@"fileSize"];
        _duration = [coder decodeDoubleForKey:@"duration"];
        _customTitle = [coder decodeObjectOfClass:[NSString class] forKey:@"customTitle"];
    }
    return self;
}

#pragma mark - Private Helpers

- (NSString *)safeFileBaseNameFromTitle:(NSString *)title {
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?\"<>|*"];
    NSString *sanitized = [[title componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@" "];
    sanitized = [sanitized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (sanitized.length == 0) {
        return @"video";
    }
    if (sanitized.length > 60) {
        return [sanitized substringToIndex:60];
    }
    return sanitized;
}

@end
