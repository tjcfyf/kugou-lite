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

    // 3.5.7 起 SDK 要求先同意隐私授权，否则所有接口（包括初始化/拉起 QQ）都会被静默拦截。
    [TencentOAuth setIsUserAgreedAuthorization:YES];

    self.oauth = [[TencentOAuth alloc] initWithAppId:@"101706348" andDelegate:(id<TencentSessionDelegate>)self];
    self.oauth.redirectURI = @"tencent101706348://tauth.qq.com/";
    self.oauth.authMode = kAuthModeClientSideToken;

    BOOL started = [self.oauth authorize:@[@"get_user_info"]];
    if (!started) {
        [self finish:nil openid:nil error:@"QQ SDK 没有成功发起授权，请确认已安装手机 QQ"];
    }
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
