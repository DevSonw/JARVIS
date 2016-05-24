//
//  JVSConvert.h
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import "JVSBridge.h"
#import "JVSClassConfig.h"

extern NSNumber *JVSConvertEnumValue(const char *, NSDictionary *, NSNumber *, id);

@interface JVSConvert : NSObject

+ (JVSClassConfig *)JVSClassConfig:(id)json bridge:(JVSBridge *)bridge;
+ (id)JVSModule:(id)json bridge:(JVSBridge *)bridge;

+ (id)Array:(id)json selector:(SEL)selector bridge:(JVSBridge *)bridge;
+ (id)Array:(id)json selector:(SEL)selector;

+ (id)id:(id)json;

+ (BOOL)BOOL:(id)json;
+ (double)double:(id)json;
+ (float)float:(id)json;
+ (int)int:(id)json;

+ (long long)long_long:(id)json;

+ (int64_t)int64_t:(id)json;
+ (uint64_t)uint64_t:(id)json;

+ (NSInteger)NSInteger:(id)json;
+ (NSUInteger)NSUInteger:(id)json;

+ (NSArray *)NSArray:(id)json;
+ (NSDictionary *)NSDictionary:(id)json;
+ (NSString *)NSString:(id)json;
+ (NSNumber *)NSNumber:(id)json;

+ (NSSet *)NSSet:(id)json;

+(NSStringEncoding)NSStringEncoding:(id)json;

+ (NSData *)NSData:(id)json;
//+ (NSIndexSet *)NSIndexSet:(id)json;

+ (NSURL *)NSURL:(id)json;
+ (NSURLRequest *)NSURLRequest:(id)json;

typedef NSURL JVSFileURL;
//+ (JVSFileURL *)JVSFileURL:(id)json;

+ (NSDate *)NSDate:(id)json;
+ (NSTimeZone *)NSTimeZone:(id)json;
+ (NSTimeInterval)NSTimeInterval:(id)json;

+ (NSLineBreakMode)NSLineBreakMode:(id)json;
+ (NSTextAlignment)NSTextAlignment:(id)json;
+ (NSUnderlineStyle)NSUnderlineStyle:(id)json;
+ (NSWritingDirection)NSWritingDirection:(id)json;
+ (UITextAutocapitalizationType)UITextAutocapitalizationType:(id)json;
+ (UITextFieldViewMode)UITextFieldViewMode:(id)json;
+ (UIKeyboardType)UIKeyboardType:(id)json;
+ (UIKeyboardAppearance)UIKeyboardAppearance:(id)json;
+ (UIReturnKeyType)UIReturnKeyType:(id)json;

+ (UIViewContentMode)UIViewContentMode:(id)json;
+ (UIBarStyle)UIBarStyle:(id)json;

+ (CGFloat)CGFloat:(id)json;
+ (CGPoint)CGPoint:(id)json;
+ (CGSize)CGSize:(id)json;
+ (CGRect)CGRect:(id)json;
+ (UIEdgeInsets)UIEdgeInsets:(id)json;

+ (CGLineCap)CGLineCap:(id)json;
+ (CGLineJoin)CGLineJoin:(id)json;

+ (CATransform3D)CATransform3D:(id)json;
+ (CGAffineTransform)CGAffineTransform:(id)json;

+ (UIColor *)UIColor:(id)json;
+ (CGColorRef)CGColor:(id)json CF_RETURNS_NOT_RETAINED;

+ (UIFont *)UIFont:(id)json;

+ (id)jsonFromNSError:(NSError *)error;
+ (id)jsonFromNSErrorDomain:(NSString *)domain code:(NSInteger)code message:(NSString *)message;

@end

/**
 * This macro is used for logging conversion errors. This is just used to
 * avoid repeating the same boilerplate for every error message.
 */
#define JVSLogConvertError(json, typeName) \
NSLog(@"JSON value '%@' of type %@ cannot be converted to %@", \
json, [json classForCoder], typeName)

/**
 * This macro is used for creating simple converter functions that just call
 * the specified getter method on the json value.
 */
#define JVS_CONVERTER(type, name, getter) \
JVS_CUSTOM_CONVERTER(type, name, [json getter])

/**
 * This macro is used for creating converter functions with arbitrary logic.
 */
#define JVS_CUSTOM_CONVERTER(type, name, code) \
+ (type)name:(id)json                          \
{                                              \
if (!JVS_DEBUG) {                            \
return code;                               \
} else {                                     \
@try {                                     \
return code;                             \
}                                          \
@catch (__unused NSException *e) {         \
JVSLogConvertError(json, @#type);        \
json = nil;                              \
return code;                             \
}                                          \
}                                            \
}

/**
 * This macro is similar to JVS_CONVERTER, but specifically geared towards
 * numeric types. It will handle string input correctly, and provides more
 * detailed error reporting if an invalid value is passed in.
 */
#define JVS_NUMBER_CONVERTER(type, getter) \
JVS_CUSTOM_CONVERTER(type, type, [JVS_DEBUG ? [self NSNumber:json] : json getter])

/**
 * This macro is used for creating converters for enum types.
 */
#define JVS_ENUM_CONVERTER(type, values, default, getter) \
+ (type)type:(id)json                                     \
{                                                         \
static NSDictionary *mapping;                           \
static dispatch_once_t onceToken;                       \
dispatch_once(&onceToken, ^{                            \
mapping = values;                                     \
});                                                     \
return [JVSConvertEnumValue(#type, mapping, @(default), json) getter]; \
}

/**
 * This macro is used for creating converters for enum types for
 * multiple enum values combined with | operator
 */
#define JVS_MULTI_ENUM_CONVERTER(type, values, default, getter) \
+ (type)type:(id)json                                     \
{                                                         \
static NSDictionary *mapping;                           \
static dispatch_once_t onceToken;                       \
dispatch_once(&onceToken, ^{                            \
mapping = values;                                     \
});                                                     \
return [JVSConvertMultiEnumValue(#type, mapping, @(default), json) getter]; \
}

/**
 * This macro is used for creating converter functions for typed arrays.
 */
#define JVS_ARRAY_CONVERTER(type)                      \
+ (NSArray<id> *)type##Array:(id)json                      \
{                                                      \
return JVSConvertArrayValue(@selector(type:), json); \
}

