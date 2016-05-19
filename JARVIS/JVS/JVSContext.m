//
//  JVSContext.m
//  JARVIS
//
//  Created by Hao on 16/5/18.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import "JVSContext.h"
#import <objc/message.h>

NSString *JVSJSValueToNSString(JSContextRef context, JSValueRef value, JSValueRef *exception)
{
    JSStringRef JSString = JSValueToStringCopy(context, value, exception);
    if (!JSString) {
        return nil;
    }
    
    CFStringRef string = JSStringCopyCFString(kCFAllocatorDefault, JSString);
    JSStringRelease(JSString);
    
    return (__bridge_transfer NSString *)string;
}

NSString *JVSJSValueToJSONString(JSContextRef context, JSValueRef value, JSValueRef *exception, unsigned indent)
{
    JSStringRef JSString = JSValueCreateJSONString(context, value, indent, exception);
    CFStringRef string = JSStringCopyCFString(kCFAllocatorDefault, JSString);
    JSStringRelease(JSString);
    
    return (__bridge_transfer NSString *)string;
}

NSError *JVSNSErrorFromJSError(JSContextRef context, JSValueRef jsError)
{
    NSString *errorMessage = jsError ? JVSJSValueToNSString(context, jsError, NULL) : @"Unknown JS error";
    NSString *details = jsError ? JVSJSValueToJSONString(context, jsError, NULL, 2) : @"No details";
    return [NSError errorWithDomain:@"JavaScriptCore" code:1 userInfo:@{NSLocalizedDescriptionKey: errorMessage, NSLocalizedFailureReasonErrorKey: details}];
}

NSString *JVSJSONStringify(id jsonObject, NSError **error)
{
    static SEL JSONKitSelector = NULL;
    static NSSet<Class> *collectionTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL selector = NSSelectorFromString(@"JSONStringWithOptions:error:");
        if ([NSDictionary instancesRespondToSelector:selector]) {
            JSONKitSelector = selector;
            collectionTypes = [NSSet setWithObjects:
                               [NSArray class], [NSMutableArray class],
                               [NSDictionary class], [NSMutableDictionary class], nil];
        }
    });
    
    // Use JSONKit if available and object is not a fragment
    if (JSONKitSelector && [collectionTypes containsObject:[jsonObject classForCoder]]) {
        return ((NSString *(*)(id, SEL, int, NSError **))objc_msgSend)(jsonObject, JSONKitSelector, 0, error);
    }
    
    // Use Foundation JSON method
    NSData *jsonData = [NSJSONSerialization
                        dataWithJSONObject:jsonObject
                        options:(NSJSONWritingOptions)NSJSONReadingAllowFragments
                        error:error];
    return jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : nil;
}

id JVSJSONParse(NSString *jsonString, BOOL mutable, NSError **error){
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        return nil;
    }
    NSJSONReadingOptions options = NSJSONReadingAllowFragments;
    if (mutable) {
        options |= NSJSONReadingMutableContainers;
    }
    return [NSJSONSerialization JSONObjectWithData:jsonData
                                           options:options
                                             error:error];
}
