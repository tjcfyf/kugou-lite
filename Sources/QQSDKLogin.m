#import "QQSDKLogin.h"
#import <TencentOpenAPI/TencentOAuth.h>

@interface QQSDKLogin ()
@property (nonatomic, strong) TencentOAuth *oauth;
@property (nonatomic, copy, nullable) QQSDKLoginCompletion completion;
@end

@implementation QQSDKLogin
+ (instancetype)shared {
    static QQSDKLogin *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[QQSDKLogin alloc] init]; });
    return shared;
}
- (BOOL)isQQInstalled { return [TencentOAuth iphoneQQInstalled]; }
- (void)startLogin:(QQSDKLoginCompletion)completion {
    self.completion = completion;
    self.oauth = [[TencentOAuth alloc] initWithAppId:@"205141" andDelegate:(id<TencentSessionDelegate>)self];
    self.oauth.redirectURI = @"tencent205141://tauth.qq.com/";
    self.oauth.authMode = kAuthModeClientSideToken;
    [self.oauth authorize:@[@"get_user_info"]];
}
+ (BOOL)handleOpenURL:(NSURL *)url { return [TencentOAuth HandleOpenURL:url]; }
- (void)finish:(NSString *)token openid:(NSString *)openid error:(NSString *)error {
    QQSDKLoginCompletion block = self.completion; self.completion = nil;
    if (block) block(token, openid, error);
}
- (void)tencentDidLogin { [self finish:self.oauth.accessToken openid:self.oauth.openId error:nil]; }
- (void)tencentDidNotLogin:(BOOL)cancelled {
    [self finish:nil openid:nil error:cancelled ? @"你取消了 QQ 授权" : @"QQ 授权失败"];
}
- (void)tencentDidNotNetWork { [self finish:nil openid:nil error:@"QQ 授权网络异常"]; }
@end
