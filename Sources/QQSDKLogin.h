#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^QQSDKLoginCompletion)(NSString * _Nullable accessToken,
                                    NSString * _Nullable openid,
                                    NSString * _Nullable errorMessage);

/// QQ 互联 iOS SDK 的薄封装：只负责拉起手机 QQ 做授权，拿到 access_token/openid。
/// 业务侧再拿这两个值去走酷狗概念版 login_by_openplat。
@interface QQSDKLogin : NSObject

+ (instancetype)shared;

- (void)startLogin:(QQSDKLoginCompletion)completion;

+ (BOOL)handleOpenURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
