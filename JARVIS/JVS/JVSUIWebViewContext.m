//
//  JVSUIWebViewContext.m
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import "JVSUIWebViewContext.h"
#import <UIKit/UIKit.h>

@interface JVSWebViewAJAXProtocol: NSURLProtocol
@end

NSString *const kWebViewContextReceiveDataNotification = @"kWebViewContextReceiveDataNotification";
static NSString *kWebViewAJAXURL = @"http://ajax/";
long kWebViewUniqueInstanceId = 0;

@interface JVSUIWebViewContext()<UIWebViewDelegate>

@property (nonatomic, weak, readonly) UIWebView *context;

@end

@implementation JVSUIWebViewContext{
    NSMutableArray *_scripts;
    NSMutableArray *_sourceURLs;
    long _instanceId;
    JVSContextCompleteBlock _completeBlock;
    BOOL _contentLoaded;
}

@synthesize receiver = _receiver;


+(void)initialize{
    [NSURLProtocol registerClass:[JVSWebViewAJAXProtocol class]];
}

-(void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kWebViewContextReceiveDataNotification object:nil];
    [_context removeFromSuperview];
}

- (void)invalidate{
    _contentLoaded = YES;
    [self.context loadHTMLString:@"<html></html>" baseURL:[NSURL URLWithString:self.baseURL]];
}

- (id)init{
    if (self = [super init]) {
        
        UIWebView *context = [UIWebView new];
        UIWindow *keyWindow = [[[UIApplication sharedApplication] delegate] window];
        if (!keyWindow) {
            [NSException raise:@"Please set window before." format:@""];
        }
        context.hidden = YES;
        [keyWindow addSubview:context];
        _context = context;
        _context.delegate = self;
        _scripts = [NSMutableArray new];
        _sourceURLs = [NSMutableArray new];
        
        kWebViewUniqueInstanceId ++;
        _instanceId = kWebViewUniqueInstanceId;
        self.baseURL = [NSString stringWithFormat:@"http://jarvis/%ld", _instanceId];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(receiver:)
                                                     name:kWebViewContextReceiveDataNotification
                                                   object:nil];
        [self addScript:[[NSString stringWithFormat:@"var __JVSContextSendCount = 0;\
                          function __JVSContextSend(method, args){\
                          try{\
                          var http = new XMLHttpRequest();\
                          http.open('POST', '%@', true);\
                          http.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');\
                          http.send(JSON.stringify({id: %ld, method: method, args: args, count: ++__JVSContextSendCount}));\
                          http.timeout = 200;\
                          }catch(e){\
                          return e;\
                          }\
                          };", kWebViewAJAXURL, _instanceId] dataUsingEncoding:NSUTF8StringEncoding] sourceURL:@"context.js"];
    }
    return self;
}

- (void)receiver:(NSNotification *)notification{
    NSDictionary *obj = notification.object;
    if ([obj isKindOfClass:[NSDictionary class]] && [[obj objectForKey:@"id"] longValue] == _instanceId) {
        [self performSelectorOnMainThread:@selector(handleSafe:) withObject:obj waitUntilDone:NO];
    }
}

- (void)handleSafe:(NSDictionary *)obj{
    if (self.receiver) {
        self.receiver(obj[@"method"], JVSJSONParse(obj[@"args"], NO, NULL));
    }
}

- (void)registerModules:(NSDictionary *)modules{
    NSData *jsonData = [NSJSONSerialization
                        dataWithJSONObject:modules
                        options:(NSJSONWritingOptions)NSJSONReadingAllowFragments
                        error:nil];
    NSMutableData *data = [[@"var __JVSModuleConfig=" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (jsonData) {
        [data appendData:jsonData];
        [_scripts insertObject:data atIndex:0];
        [_sourceURLs insertObject:@"modules.js" atIndex:0];
    } else {
        //TODO: throw error.
    }
}

- (void)addScript:(NSData *)script
        sourceURL:(NSString *)sourceURL{
    if (script) {
        [_scripts addObject:script];
        [_sourceURLs addObject:sourceURL ? sourceURL : @"undefined.js"];
    } else if( sourceURL ){
        [_scripts addObject:[NSNull null]];
        [_sourceURLs addObject:sourceURL];
    }
}

- (NSString *)htmlContext{
    NSString *str = @"";
    NSUInteger len = [_scripts count];
    for (int i = 0; i < len; i++) {
        if (_scripts[i] == [NSNull null]) {
            str = [str stringByAppendingFormat:@"<script src=\"%@\"></script>\n", _sourceURLs[i]];
        } else {
            str = [str stringByAppendingFormat:@"<script>%@</script>", [[NSString alloc] initWithData:_scripts[i] encoding:NSUTF8StringEncoding]];
        }
    }
    return [NSString stringWithFormat:@"<!DOCTYPE html><html><head><meta charset=\"UTF-8\"><title>JARVIS</title>%@</head><body></body></html>", str];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    if (_contentLoaded) {
        [self refresh];
        return NO;
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    _contentLoaded = YES;
    if (_completeBlock) {
        _completeBlock(nil);
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    _contentLoaded = YES;
    if (_completeBlock) {
        _completeBlock(error);
    }
}

- (void)refresh{
    _contentLoaded = NO;
    if(self.refreshBlock){
        self.refreshBlock();
    }
    [self.context loadHTMLString:[self htmlContext] baseURL:[NSURL URLWithString:self.baseURL]];
}

- (void)run:(JVSContextCompleteBlock)onComplete{
    _completeBlock = onComplete;
    [self performSelectorOnMainThread:@selector(refresh) withObject:nil waitUntilDone:NO];
}


- (NSError *)_execScript:(NSData *)script
               sourceURL:(NSString *)sourceURL{
    NSString *str = [[NSString alloc] initWithData:script encoding:NSUTF8StringEncoding];
    __unused NSString *ret = [self.context stringByEvaluatingJavaScriptFromString:str];
    return nil;
}


- (void)execScript:(NSData *)script
         sourceURL:(NSString *)sourceURL onComplete:(JVSContextCompleteBlock)onComplete{
    dispatch_async(dispatch_get_main_queue(), ^(void){
        NSError *err = [self _execScript:script sourceURL:sourceURL];
        if (onComplete) {
            onComplete(err);
        }
    });
}

- (void)callMethod:(NSString *)method
         arguments:(NSArray *)args{
    NSString *script = [NSString stringWithFormat:@"__JVSConextReceiver('%@', %@)", method, JVSJSONStringify(args, nil)];
    [self execScript:[script dataUsingEncoding:NSUTF8StringEncoding] sourceURL:nil onComplete:^(NSError *error) {
        if (error) {
            NSLog(@"JSError: %@", error);
        }
    }];
}

@end


@implementation JVSWebViewAJAXProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    if ([request.URL.absoluteString isEqualToString:kWebViewAJAXURL]) {
        NSString *str = request.HTTPBody ? [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding] : nil;
        id obj = nil;
        if (str.length) {
            NSError* error;
            obj = [NSJSONSerialization JSONObjectWithData:[str dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:&error];
        }
        if (obj) {
            [[NSNotificationCenter defaultCenter]
             postNotificationName:kWebViewContextReceiveDataNotification
             object:obj];
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (NSCachedURLResponse *)cachedResponse { return nil; }

- (void)startLoading
{
    NSString *str = @"OK";
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"1.1" headerFields:@{@"Access-Control-Allow-Origin": @"*"}];
    [self.client URLProtocol:self
          didReceiveResponse:response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading { }

@end

