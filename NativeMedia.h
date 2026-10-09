#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
#ifdef __cplusplus
extern "C" {
#endif
BOOL MFExtractArchive(NSString *source, NSString *destination, NSError **error);
BOOL MFConvertUSM(NSString *source, NSString *destination, NSError **error);
#ifdef __cplusplus
}
#endif
NS_ASSUME_NONNULL_END
