#import "WikipediaAppUtils.h"
#import "WMFAssetsFile.h"
#import "NSBundle+WMFInfoUtils.h"
#import <WMF/WMF-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation WikipediaAppUtils

+ (NSString *)appVersion {
    return [[NSBundle mainBundle] wmf_versionForCurrentBundleIdentifier];
}

+ (NSString *)bundleID {
    return [[NSBundle mainBundle] wmf_bundleIdentifier];
}

+ (NSString *)formFactor {
    UIUserInterfaceIdiom ff = UI_USER_INTERFACE_IDIOM();
    // We'll break; on each case, just to follow good form.
    switch (ff) {
        case UIUserInterfaceIdiomPad:
            return @"Tablet";
            break;

        case UIUserInterfaceIdiomPhone:
            return @"Phone";
            break;

        default:
            return @"Other";
            break;
    }
}

+ (NSString *)versionedUserAgent {
    UIDevice *d = [UIDevice currentDevice];
    return [NSString stringWithFormat:@"WikipediaApp/%@ (%@ %@; %@)",
                                      [[NSBundle mainBundle] wmf_debugVersion],
                                      [d systemName],
                                      [d systemVersion],
                                      [self formFactor]];
}

static WMFAssetsFile *_Nullable languageFile = nil;

+ (NSString *)languageNameForCode:(NSString *)code {
    if (!languageFile) {
        languageFile = [[WMFAssetsFile alloc] initWithFileType:WMFAssetsFileTypeLanguages];
    }

    return [languageFile.array wmf_match:^BOOL(NSDictionary *obj) {
        return [obj[@"code"] isEqualToString:code];
    }][@"name"];
}

+ (NSString *)assetsPath {
    return [[NSBundle wmf] pathForResource:@"assets" ofType:nil];
}

@end

NS_ASSUME_NONNULL_END
