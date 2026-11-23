#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^QQSDKLoginCompletion)(NSString * _Nullable accessToken,
                                    NSString * _Nullable openid,
                                    NSString * _Nullable errorMessage);

@interface QQSDKLogin : NSObject

+ (instancetype)shared;
- (void)startLogin:(QQSDKLoginCompletion)completion;
+ (BOOL)handleOpenURL:(NSURL *)url;
- (BOOL)isQQInstalled;

@end

NS_ASSUME_NONNULL_END
