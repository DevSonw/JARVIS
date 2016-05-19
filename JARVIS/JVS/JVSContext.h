//
//  JVSContext.h
//  JARVIS
//
//  Created by Hao on 16/5/18.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

#ifndef JVS_DEBUG
#if DEBUG
#define JVS_DEBUG 1
#else
#define JVS_DEBUG 0
#endif
#endif

typedef void (^JVSContextCompleteBlock)(NSError *error);

typedef void (^JVSContextMethod)(NSString *method, NSArray *args);

extern NSString *JVSJSValueToNSString(JSContextRef context, JSValueRef value, JSValueRef *exception);
extern NSString *JVSJSValueToJSONString(JSContextRef context, JSValueRef value, JSValueRef *exception, unsigned indent);
extern NSError *JVSNSErrorFromJSError(JSContextRef context, JSValueRef jsError);
extern NSString *JVSJSONStringify(id jsonObject, NSError **error);
extern id JVSJSONParse(NSString *jsonString, BOOL mutable, NSError **error);

@protocol JVSContext

@property(nonatomic, copy) JVSContextMethod receiver;

/**
 Set the module config
 @param modules The config
 */
- (void)registerModules:(NSDictionary *)modules;

- (void)addScript:(NSData *)script
        sourceURL:(NSString *)sourceURL;

- (void)run:(JVSContextCompleteBlock)onComplete;

- (void)callMethod:(NSString *)method
         arguments:(NSArray *)args;

- (void)invalidate;

@end
