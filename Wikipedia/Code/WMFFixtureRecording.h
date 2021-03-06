
NS_ASSUME_NONNULL_BEGIN

#if DEBUG && TARGET_IPHONE_SIMULATOR

static const char *const WMFFixtureDirectoryEnvKey = "WMF_FIXTURE_DIRECTORY";

typedef void (^WMFFixtureRecordingBlock)(NSString *filename);

#define WMFRecordDataFixture(data, folder, name) _WMFRecordDataFixture((data), (folder), (name))
extern void _WMFRecordDataFixture(NSData *data, NSString *folder, NSString *name);

extern void _WMFRecordFixtureWithBlock(NSString *folder,
                                       NSString *filename,
                                       WMFFixtureRecordingBlock block);
#else

#define WMFRecordDataFixture(...)

#endif

NS_ASSUME_NONNULL_END
