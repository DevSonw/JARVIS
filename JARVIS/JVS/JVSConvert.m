//
//  JVSConvert.m
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import "JVSConvert.h"
#import "JVSExport.h"

@implementation JVSConvert


+ (JVSClassConfig *)JVSClassConfig:(id)json bridge:(JVSBridge *)bridge{
    json = [JVSConvert NSDictionary:json];
    if (json) {
        return [JVSClassConfig ClassConfigWithBridge:bridge setting:json];
    }
    return nil;
}

+ (id)JVSModule:(id)json bridge:(JVSBridge *)bridge{
    
    //Instance....
    JVSClassConfig *config = [self JVSClassConfig:json bridge:bridge];
    id value = nil;
    if (config) {
        if (config.loaded) {
            value = [config getInstance];
        } else {
            //Create default instance.
            if ([config.moduleClass respondsToSelector:@selector(instanceWithConfig:)]) {
                value = [config.moduleClass performSelector:@selector(instanceWithConfig:) withObject:config];
            } else {
                value = [config.moduleClass new];
            }
            if (value) {
                [config mapInstance:value];
            }
        }
    }
    return value;
}

+ (id)JVSModuleArray:(id)json bridge:(JVSBridge *)bridge{
    return [self Array:json selector:@selector(JVSModule:bridge:) bridge:bridge];
}

+ (id)Array:(id)json selector:(SEL)selector{
    json = [self NSArray:json];
    if (json) {
        NSMutableArray *ar = [NSMutableArray array];
        for (id s in json) {
            id module = [self performSelector:selector withObject:s];
            [ar addObject:module ? module : [NSNull null]];
        }
        return ar;
    }
    return nil;
}

+ (id)Array:(id)json selector:(SEL)selector bridge:(JVSBridge *)bridge{
    json = [self NSArray:json];
    if (json) {
        NSMutableArray *ar = [NSMutableArray array];
        for (id s in json) {
            id module = [self performSelector:selector withObject:s withObject:bridge];
            [ar addObject:module ? module : [NSNull null]];
        }
        return ar;
    }
    return nil;
    
}

JVS_CONVERTER(id, id, self)

JVS_CONVERTER(BOOL, BOOL, boolValue)
JVS_NUMBER_CONVERTER(double, doubleValue)
JVS_NUMBER_CONVERTER(float, floatValue)
JVS_NUMBER_CONVERTER(int, intValue)

JVS_CUSTOM_CONVERTER(long long, long_long, [JVS_DEBUG ? [self NSNumber:json] : json longLongValue]);

JVS_NUMBER_CONVERTER(int64_t, longLongValue);
JVS_NUMBER_CONVERTER(uint64_t, unsignedLongLongValue);

JVS_NUMBER_CONVERTER(NSInteger, integerValue)
JVS_NUMBER_CONVERTER(NSUInteger, unsignedIntegerValue)

/**
 * This macro is used for creating converter functions for directly
 * representable json values that require no conversion.
 */
#if JVS_DEBUG
#define JVS_JSON_CONVERTER(type)           \
+ (type *)type:(id)json                    \
{                                          \
if (json == [NSNull null]) return nil; \
if ([json isKindOfClass:[type class]]) { \
return json;                           \
} else if (json) {                       \
JVSLogConvertError(json, @#type);      \
}                                        \
return nil;                              \
}
#else
#define JVS_JSON_CONVERTER(type)           \
+ (type *)type:(id)json { \
if (json == [NSNull null]) return nil; \
if ([json isKindOfClass:[type class]]){ \
return json; \
} \
return nil;                              \
}
#endif

JVS_JSON_CONVERTER(NSArray)
JVS_JSON_CONVERTER(NSDictionary)
JVS_JSON_CONVERTER(NSString)
JVS_JSON_CONVERTER(NSNumber)

JVS_CUSTOM_CONVERTER(NSSet *, NSSet, [NSSet setWithArray:json])

+(NSStringEncoding)NSStringEncoding:(id)json{
    if (!json || json == [NSNull null]) {
        json = @"utf-8";
    }
    NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding((CFStringRef)json));
    return encoding;
}

+(NSData *)NSData:(id)json{
    if ([json isKindOfClass:[NSData class]]) {
        return json;
    } else if ([json isKindOfClass:[NSString class]]) {
        return [json dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        NSData *data = [json[@"data"] dataUsingEncoding:[self NSStringEncoding:json[@"encoding"]]];
        if (json[@"base64"] && [json[@"base64"] boolValue]) {
            data = [[NSData alloc] initWithBase64EncodedData:data options:0];
        }
        return data;
    }
    return nil;
}

//
//+ (NSIndexSet *)NSIndexSet:(id)json
//{
//    json = [self NSNumberArray:json];
//    NSMutableIndexSet *indexSet = [NSMutableIndexSet new];
//    for (NSNumber *number in json) {
//        NSInteger index = number.integerValue;
//        if (JVS_DEBUG && index < 0) {
//            JVSLogError(@"Invalid index value %zd. Indices must be positive.", index);
//        }
//        [indexSet addIndex:index];
//    }
//    return indexSet;
//}

+ (NSURL *)NSURL:(id)json
{
    NSString *path = [self NSString:json];
    if (!path) {
        return nil;
    }
    
    @try { // NSURL has a history of crashing with bad input, so let's be safe
        
        NSURL *URL = [NSURL URLWithString:path];
        if (URL.scheme) { // Was a well-formed absolute URL
            return URL;
        }
        
        // Check if it has a scheme
        if ([path rangeOfString:@":"].location != NSNotFound) {
            path = [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            URL = [NSURL URLWithString:path];
            if (URL) {
                return URL;
            }
        }
        
        // Assume that it's a local path
        path = path.stringByRemovingPercentEncoding;
        if ([path hasPrefix:@"~"]) {
            // Path is inside user directory
            path = path.stringByExpandingTildeInPath;
        } else if (!path.absolutePath) {
            // Assume it's a resource path
            path = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:path];
        }
        if (!(URL = [NSURL fileURLWithPath:path])) {
            JVSLogConvertError(json, @"a valid URL");
        }
        return URL;
    }
    @catch (__unused NSException *e) {
        JVSLogConvertError(json, @"a valid URL");
        return nil;
    }
}

+ (NSURLRequest *)NSURLRequest:(id)json
{
    NSURL *URL = [self NSURL:json];
    return URL ? [NSURLRequest requestWithURL:URL] : nil;
}

//+ (JVSFileURL *)JVSFileURL:(id)json
//{
//    NSURL *fileURL = [self NSURL:json];
//    if (!fileURL.fileURL) {
//        JVSLogError(@"URI must be a local file, '%@' isn't.", fileURL);
//        return nil;
//    }
//    if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path]) {
//        JVSLogError(@"File '%@' could not be found.", fileURL);
//        return nil;
//    }
//    return fileURL;
//}

+ (NSDate *)NSDate:(id)json
{
    if ([json isKindOfClass:[NSNumber class]]) {
        return [NSDate dateWithTimeIntervalSince1970:[self NSTimeInterval:json]];
    } else if ([json isKindOfClass:[NSString class]]) {
        static NSDateFormatter *formatter;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [NSDateFormatter new];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        });
        NSDate *date = [formatter dateFromString:json];
        if (!date) {
            //            JVSLogError(@"JSON String '%@' could not be interpreted as a date. "
            //                        "Expected format: YYYY-MM-DD'T'HH:mm:ss.sssZ", json);
        }
        return date;
    } else if (json) {
        JVSLogConvertError(json, @"a date");
    }
    return nil;
}

// JS Standard for time is milliseconds
JVS_CUSTOM_CONVERTER(NSTimeInterval, NSTimeInterval, [self double:json] / 1000.0)

// JS standard for time zones is minutes.
JVS_CUSTOM_CONVERTER(NSTimeZone *, NSTimeZone, [NSTimeZone timeZoneForSecondsFromGMT:[self double:json] * 60.0])

NSNumber *JVSConvertEnumValue(const char *typeName, NSDictionary *mapping, NSNumber *defaultValue, id json)
{
    if (!json) {
        return defaultValue;
    }
    if ([json isKindOfClass:[NSNumber class]]) {
        NSArray *allValues = mapping.allValues;
        if ([allValues containsObject:json] || [json isEqual:defaultValue]) {
            return json;
        }
        //        JVSLogError(@"Invalid %s '%@'. should be one of: %@", typeName, json, allValues);
        return defaultValue;
    }
    if (JVS_DEBUG && ![json isKindOfClass:[NSString class]]) {
        //        JVSLogError(@"Expected NSNumber or NSString for %s, received %@: %@",
        //                    typeName, [json classForCoder], json);
    }
    id value = mapping[json];
    if (JVS_DEBUG && !value && [json description].length > 0) {
        //        JVSLogError(@"Invalid %s '%@'. should be one of: %@", typeName, json, [[mapping allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)]);
    }
    return value ?: defaultValue;
}

NSNumber *JVSConvertMultiEnumValue(const char *typeName, NSDictionary *mapping, NSNumber *defaultValue, id json)
{
    if ([json isKindOfClass:[NSArray class]]) {
        if ([json count] == 0) {
            return defaultValue;
        }
        long long result = 0;
        for (id arrayElement in json) {
            NSNumber *value = JVSConvertEnumValue(typeName, mapping, defaultValue, arrayElement);
            result |= value.longLongValue;
        }
        return @(result);
    }
    return JVSConvertEnumValue(typeName, mapping, defaultValue, json);
}

JVS_ENUM_CONVERTER(NSLineBreakMode, (@{
                                       @"wordWrapping": @(NSLineBreakByWordWrapping),
                                       @"charWrapping": @(NSLineBreakByCharWrapping),
                                       @"clipping": @(NSLineBreakByClipping),
                                       @"truncatingHead": @(NSLineBreakByTruncatingHead),
                                       @"truncatingTail": @(NSLineBreakByTruncatingTail),
                                       @"truncatingMiddle": @(NSLineBreakByTruncatingMiddle),
                                       }), NSLineBreakByWordWrapping, integerValue)

JVS_ENUM_CONVERTER(NSTextAlignment, (@{
                                       @"auto": @(NSTextAlignmentNatural),
                                       @"left": @(NSTextAlignmentLeft),
                                       @"center": @(NSTextAlignmentCenter),
                                       @"right": @(NSTextAlignmentRight),
                                       @"justify": @(NSTextAlignmentJustified),
                                       }), NSTextAlignmentNatural, integerValue)

JVS_ENUM_CONVERTER(NSUnderlineStyle, (@{
                                        @"solid": @(NSUnderlineStyleSingle),
                                        @"double": @(NSUnderlineStyleDouble),
                                        @"dotted": @(NSUnderlinePatternDot | NSUnderlineStyleSingle),
                                        @"dashed": @(NSUnderlinePatternDash | NSUnderlineStyleSingle),
                                        }), NSUnderlineStyleSingle, integerValue)

JVS_ENUM_CONVERTER(NSWritingDirection, (@{
                                          @"auto": @(NSWritingDirectionNatural),
                                          @"ltr": @(NSWritingDirectionLeftToRight),
                                          @"rtl": @(NSWritingDirectionRightToLeft),
                                          }), NSWritingDirectionNatural, integerValue)

JVS_ENUM_CONVERTER(UITextAutocapitalizationType, (@{
                                                    @"none": @(UITextAutocapitalizationTypeNone),
                                                    @"words": @(UITextAutocapitalizationTypeWords),
                                                    @"sentences": @(UITextAutocapitalizationTypeSentences),
                                                    @"characters": @(UITextAutocapitalizationTypeAllCharacters)
                                                    }), UITextAutocapitalizationTypeSentences, integerValue)

JVS_ENUM_CONVERTER(UITextFieldViewMode, (@{
                                           @"never": @(UITextFieldViewModeNever),
                                           @"while-editing": @(UITextFieldViewModeWhileEditing),
                                           @"unless-editing": @(UITextFieldViewModeUnlessEditing),
                                           @"always": @(UITextFieldViewModeAlways),
                                           }), UITextFieldViewModeNever, integerValue)

JVS_ENUM_CONVERTER(UIKeyboardType, (@{
                                      @"default": @(UIKeyboardTypeDefault),
                                      @"ascii-capable": @(UIKeyboardTypeASCIICapable),
                                      @"numbers-and-punctuation": @(UIKeyboardTypeNumbersAndPunctuation),
                                      @"url": @(UIKeyboardTypeURL),
                                      @"number-pad": @(UIKeyboardTypeNumberPad),
                                      @"phone-pad": @(UIKeyboardTypePhonePad),
                                      @"name-phone-pad": @(UIKeyboardTypeNamePhonePad),
                                      @"email-address": @(UIKeyboardTypeEmailAddress),
                                      @"decimal-pad": @(UIKeyboardTypeDecimalPad),
                                      @"twitter": @(UIKeyboardTypeTwitter),
                                      @"web-search": @(UIKeyboardTypeWebSearch),
                                      // Added for Android compatibility
                                      @"numeric": @(UIKeyboardTypeDecimalPad),
                                      }), UIKeyboardTypeDefault, integerValue)

JVS_ENUM_CONVERTER(UIKeyboardAppearance, (@{
                                            @"default": @(UIKeyboardAppearanceDefault),
                                            @"light": @(UIKeyboardAppearanceLight),
                                            @"dark": @(UIKeyboardAppearanceDark),
                                            }), UIKeyboardAppearanceDefault, integerValue)

JVS_ENUM_CONVERTER(UIReturnKeyType, (@{
                                       @"default": @(UIReturnKeyDefault),
                                       @"go": @(UIReturnKeyGo),
                                       @"google": @(UIReturnKeyGoogle),
                                       @"join": @(UIReturnKeyJoin),
                                       @"next": @(UIReturnKeyNext),
                                       @"route": @(UIReturnKeyRoute),
                                       @"search": @(UIReturnKeySearch),
                                       @"send": @(UIReturnKeySend),
                                       @"yahoo": @(UIReturnKeyYahoo),
                                       @"done": @(UIReturnKeyDone),
                                       @"emergency-call": @(UIReturnKeyEmergencyCall),
                                       }), UIReturnKeyDefault, integerValue)

JVS_ENUM_CONVERTER(UIViewContentMode, (@{
                                         @"scale-to-fill": @(UIViewContentModeScaleToFill),
                                         @"scale-aspect-fit": @(UIViewContentModeScaleAspectFit),
                                         @"scale-aspect-fill": @(UIViewContentModeScaleAspectFill),
                                         @"redraw": @(UIViewContentModeRedraw),
                                         @"center": @(UIViewContentModeCenter),
                                         @"top": @(UIViewContentModeTop),
                                         @"bottom": @(UIViewContentModeBottom),
                                         @"left": @(UIViewContentModeLeft),
                                         @"right": @(UIViewContentModeRight),
                                         @"top-left": @(UIViewContentModeTopLeft),
                                         @"top-right": @(UIViewContentModeTopRight),
                                         @"bottom-left": @(UIViewContentModeBottomLeft),
                                         @"bottom-right": @(UIViewContentModeBottomRight),
                                         // Cross-platform values
                                         @"cover": @(UIViewContentModeScaleAspectFill),
                                         @"contain": @(UIViewContentModeScaleAspectFit),
                                         @"stretch": @(UIViewContentModeScaleToFill),
                                         }), UIViewContentModeScaleAspectFill, integerValue)

JVS_ENUM_CONVERTER(UIBarStyle, (@{
                                  @"default": @(UIBarStyleDefault),
                                  @"black": @(UIBarStyleBlack),
                                  }), UIBarStyleDefault, integerValue)

// TODO: normalise the use of w/width so we can do away with the alias values (#6566645)
static void JVSConvertCGStructValue(const char *type, NSArray *fields, NSDictionary *aliases, CGFloat *result, id json)
{
    NSUInteger count = fields.count;
    if ([json isKindOfClass:[NSArray class]]) {
        if (JVS_DEBUG && [json count] != count) {
            //            JVSLogError(@"Expected array with count %zd, but count is %zd: %@", count, [json count], json);
        } else {
            for (NSUInteger i = 0; i < count; i++) {
                result[i] = [JVSConvert CGFloat:json[i]];
            }
        }
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        if (aliases.count) {
            json = [json mutableCopy];
            for (NSString *alias in aliases) {
                NSString *key = aliases[alias];
                NSNumber *number = json[alias];
                if (number != nil) {
                    //                    JVSLogWarn(@"Using deprecated '%@' property for '%s'. Use '%@' instead.", alias, type, key);
                    ((NSMutableDictionary *)json)[key] = number;
                }
            }
        }
        for (NSUInteger i = 0; i < count; i++) {
            result[i] = [JVSConvert CGFloat:json[fields[i]]];
        }
    } else if (JVS_DEBUG && json) {
        JVSLogConvertError(json, @(type));
    }
}

/**
 * This macro is used for creating converter functions for structs that consist
 * of a number of CGFloat properties, such as CGPoint, CGRect, etc.
 */
#define JVS_CGSTRUCT_CONVERTER(type, values, aliases) \
+ (type)type:(id)json                                 \
{                                                     \
static NSArray *fields;                             \
static dispatch_once_t onceToken;                   \
dispatch_once(&onceToken, ^{                        \
fields = values;                                  \
});                                                 \
type result;                                        \
JVSConvertCGStructValue(#type, fields, aliases, (CGFloat *)&result, json); \
return result;                                      \
}

JVS_CUSTOM_CONVERTER(CGFloat, CGFloat, [self double:json])
JVS_CGSTRUCT_CONVERTER(CGPoint, (@[@"x", @"y"]), (@{@"l": @"x", @"t": @"y"}))
JVS_CGSTRUCT_CONVERTER(CGSize, (@[@"width", @"height"]), (@{@"w": @"width", @"h": @"height"}))
JVS_CGSTRUCT_CONVERTER(CGRect, (@[@"x", @"y", @"width", @"height"]), (@{@"l": @"x", @"t": @"y", @"w": @"width", @"h": @"height"}))
JVS_CGSTRUCT_CONVERTER(UIEdgeInsets, (@[@"top", @"left", @"bottom", @"right"]), nil)

JVS_ENUM_CONVERTER(CGLineJoin, (@{
                                  @"miter": @(kCGLineJoinMiter),
                                  @"round": @(kCGLineJoinRound),
                                  @"bevel": @(kCGLineJoinBevel),
                                  }), kCGLineJoinMiter, intValue)

JVS_ENUM_CONVERTER(CGLineCap, (@{
                                 @"butt": @(kCGLineCapButt),
                                 @"round": @(kCGLineCapRound),
                                 @"square": @(kCGLineCapSquare),
                                 }), kCGLineCapButt, intValue)

JVS_CGSTRUCT_CONVERTER(CATransform3D, (@[
                                         @"m11", @"m12", @"m13", @"m14",
                                         @"m21", @"m22", @"m23", @"m24",
                                         @"m31", @"m32", @"m33", @"m34",
                                         @"m41", @"m42", @"m43", @"m44"
                                         ]), nil)

JVS_CGSTRUCT_CONVERTER(CGAffineTransform, (@[
                                             @"a", @"b", @"c", @"d", @"tx", @"ty"
                                             ]), nil)

+ (UIColor *)UIColor:(id)json
{
    if (!json) {
        return nil;
    }
    if ([json isKindOfClass:[NSString class]]) {
        json = [json stringByReplacingOccurrencesOfString:@"'" withString:@""];
        if ([json hasPrefix:@"#"]) {
            const char *s = [json cStringUsingEncoding:NSASCIIStringEncoding];
            if (*s == '#') {
                ++s;
            }
            unsigned long long value = strtoll(s, nil, 16);
            int r, g, b, a;
            switch (strlen(s)) {
                case 2:
                    // xx
                    r = g = b = (int)value;
                    a = 255;
                    break;
                case 3:
                    // RGB
                    r = ((value & 0xf00) >> 8);
                    g = ((value & 0x0f0) >> 4);
                    b = ((value & 0x00f) >> 0);
                    r = r * 16 + r;
                    g = g * 16 + g;
                    b = b * 16 + b;
                    a = 255;
                    break;
                case 6:
                    // RRGGBB
                    r = (value & 0xff0000) >> 16;
                    g = (value & 0x00ff00) >>  8;
                    b = (value & 0x0000ff) >>  0;
                    a = 255;
                    break;
                default:
                    // RRGGBBAA
                    r = (value & 0xff000000) >> 24;
                    g = (value & 0x00ff0000) >> 16;
                    b = (value & 0x0000ff00) >>  8;
                    a = (value & 0x000000ff) >>  0;
                    break;
            }
            return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:a/255.0f];
        }
        else
        {
            json = [json stringByAppendingString:@"Color"];
            SEL colorSel = NSSelectorFromString(json);
            if ([UIColor respondsToSelector:colorSel]) {
                return [UIColor performSelector:colorSel];
            }
            return nil;
        }
    } else if([json isKindOfClass:[UIColor class]]){
        return (UIColor *)json;
    } else if ([json isKindOfClass:[NSNumber class]]) {
        NSUInteger argb = [json integerValue];
        CGFloat a = ((argb >> 24) & 0xFF) / 255.0;
        CGFloat r = ((argb >> 16) & 0xFF) / 255.0;
        CGFloat g = ((argb >> 8) & 0xFF) / 255.0;
        CGFloat b = (argb & 0xFF) / 255.0;
        return [UIColor colorWithRed:r green:g blue:b alpha:a];
    } else {
        return nil;
    }
}

+ (CGColorRef)CGColor:(id)json
{
    return [self UIColor:json].CGColor;
}

#if !defined(__IPHONE_8_2) || __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_2

// These constants are defined in iPhone SDK 8.2, but the app cannot run on
// iOS < 8.2 unless we redefine them here. If you target iOS 8.2 or above
// as a base target, the standard constants will be used instead.

#define UIFontWeightUltraLight -0.8
#define UIFontWeightThin -0.6
#define UIFontWeightLight -0.4
#define UIFontWeightRegular 0
#define UIFontWeightMedium 0.23
#define UIFontWeightSemibold 0.3
#define UIFontWeightBold 0.4
#define UIFontWeightHeavy 0.56
#define UIFontWeightBlack 0.62

#endif

typedef CGFloat JVSFontWeight;
JVS_ENUM_CONVERTER(JVSFontWeight, (@{
                                     @"normal": @(UIFontWeightRegular),
                                     @"bold": @(UIFontWeightBold),
                                     @"100": @(UIFontWeightUltraLight),
                                     @"200": @(UIFontWeightThin),
                                     @"300": @(UIFontWeightLight),
                                     @"400": @(UIFontWeightRegular),
                                     @"500": @(UIFontWeightMedium),
                                     @"600": @(UIFontWeightSemibold),
                                     @"700": @(UIFontWeightBold),
                                     @"800": @(UIFontWeightHeavy),
                                     @"900": @(UIFontWeightBlack),
                                     }), UIFontWeightRegular, doubleValue)

typedef BOOL JVSFontStyle;
JVS_ENUM_CONVERTER(JVSFontStyle, (@{
                                    @"normal": @NO,
                                    @"italic": @YES,
                                    @"oblique": @YES,
                                    }), NO, boolValue)

static JVSFontWeight JVSWeightOfFont(UIFont *font)
{
    static NSDictionary *nameToWeight;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        nameToWeight = @{
                         @"normal": @(UIFontWeightRegular),
                         @"bold": @(UIFontWeightBold),
                         @"ultralight": @(UIFontWeightUltraLight),
                         @"thin": @(UIFontWeightThin),
                         @"light": @(UIFontWeightLight),
                         @"regular": @(UIFontWeightRegular),
                         @"medium": @(UIFontWeightMedium),
                         @"semibold": @(UIFontWeightSemibold),
                         @"bold": @(UIFontWeightBold),
                         @"heavy": @(UIFontWeightHeavy),
                         @"black": @(UIFontWeightBlack),
                         };
    });
    
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    JVSFontWeight weight = [traits[UIFontWeightTrait] doubleValue];
    if (weight == 0.0) {
        for (NSString *name in nameToWeight) {
            if ([font.fontName.lowercaseString hasSuffix:name]) {
                return [nameToWeight[name] doubleValue];
            }
        }
    }
    return weight;
}

static BOOL JVSFontIsItalic(UIFont *font)
{
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    UIFontDescriptorSymbolicTraits symbolicTraits = [traits[UIFontSymbolicTrait] unsignedIntValue];
    return (symbolicTraits & UIFontDescriptorTraitItalic) != 0;
}

static BOOL JVSFontIsCondensed(UIFont *font)
{
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    UIFontDescriptorSymbolicTraits symbolicTraits = [traits[UIFontSymbolicTrait] unsignedIntValue];
    return (symbolicTraits & UIFontDescriptorTraitCondensed) != 0;
}

+ (UIFont *)UIFont:(id)json
{
    if ([json isKindOfClass:[NSString class]]) {
        return [UIFont fontWithName:json size:17.f];
    } else if([json isKindOfClass:[NSDictionary class]]){
        NSString *familyName = json[@"family"];
        float size = [json[@"size"] floatValue];
        if (!size) {
            size = 17.f;
        }
        if (!familyName) {
            return [UIFont systemFontOfSize:size];
        }
        return [UIFont fontWithName:familyName size:size];
    } else if([json isKindOfClass:[UIFont class]]){
        return json;
    }
    return nil;
    
    //    json = [self NSDictionary:json];
    //    return [self UIFont:nil
    //             withFamily:json[@"fontFamily"]
    //                   size:json[@"fontSize"]
    //                 weight:json[@"fontWeight"]
    //                  style:json[@"fontStyle"]
    //        scaleMultiplier:1.0f];
}

+ (UIFont *)UIFont:(UIFont *)font withSize:(id)json
{
    return [self UIFont:font withFamily:nil size:json weight:nil style:nil scaleMultiplier:1.0];
}

+ (UIFont *)UIFont:(UIFont *)font withWeight:(id)json
{
    return [self UIFont:font withFamily:nil size:nil weight:json style:nil scaleMultiplier:1.0];
}

+ (UIFont *)UIFont:(UIFont *)font withStyle:(id)json
{
    return [self UIFont:font withFamily:nil size:nil weight:nil style:json scaleMultiplier:1.0];
}

+ (UIFont *)UIFont:(UIFont *)font withFamily:(id)json
{
    return [self UIFont:font withFamily:json size:nil weight:nil style:nil scaleMultiplier:1.0];
}

+ (UIFont *)UIFont:(UIFont *)font withFamily:(id)family
              size:(id)size weight:(id)weight style:(id)style
   scaleMultiplier:(CGFloat)scaleMultiplier
{
    // Defaults
    NSString *const JVSDefaultFontFamily = @"System";
    NSString *const JVSIOS8SystemFontFamily = @"Helvetica Neue";
    const JVSFontWeight JVSDefaultFontWeight = UIFontWeightRegular;
    const CGFloat JVSDefaultFontSize = 14;
    
    // Initialize properties to defaults
    CGFloat fontSize = JVSDefaultFontSize;
    JVSFontWeight fontWeight = JVSDefaultFontWeight;
    NSString *familyName = JVSDefaultFontFamily;
    BOOL isItalic = NO;
    BOOL isCondensed = NO;
    
    if (font) {
        familyName = font.familyName ?: JVSDefaultFontFamily;
        fontSize = font.pointSize ?: JVSDefaultFontSize;
        fontWeight = JVSWeightOfFont(font);
        isItalic = JVSFontIsItalic(font);
        isCondensed = JVSFontIsCondensed(font);
    }
    
    // Get font attributes
    fontSize = [self CGFloat:size] ?: fontSize;
    if (scaleMultiplier > 0.0 && scaleMultiplier != 1.0) {
        fontSize = round(fontSize * scaleMultiplier);
    }
    familyName = [self NSString:family] ?: familyName;
    isItalic = style ? [self JVSFontStyle:style] : isItalic;
    fontWeight = weight ? [self JVSFontWeight:weight] : fontWeight;
    
    // Handle system font as special case. This ensures that we preserve
    // the specific metrics of the standard system font as closely as possible.
    if ([familyName isEqual:JVSDefaultFontFamily]) {
        if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
            font = [UIFont systemFontOfSize:fontSize weight:fontWeight];
            if (isItalic || isCondensed) {
                UIFontDescriptor *fontDescriptor = [font fontDescriptor];
                UIFontDescriptorSymbolicTraits symbolicTraits = fontDescriptor.symbolicTraits;
                if (isItalic) {
                    symbolicTraits |= UIFontDescriptorTraitItalic;
                }
                if (isCondensed) {
                    symbolicTraits |= UIFontDescriptorTraitCondensed;
                }
                fontDescriptor = [fontDescriptor fontDescriptorWithSymbolicTraits:symbolicTraits];
                font = [UIFont fontWithDescriptor:fontDescriptor size:fontSize];
            }
            return font;
        } else {
            // systemFontOfSize:weight: isn't available prior to iOS 8.2, so we
            // fall back to finding the correct font manually, by linear search.
            familyName = JVSIOS8SystemFontFamily;
        }
    }
    
    // Gracefully handle being given a font name rather than font family, for
    // example: "Helvetica Light Oblique" rather than just "Helvetica".
    if ([UIFont fontNamesForFamilyName:familyName].count == 0) {
        font = [UIFont fontWithName:familyName size:fontSize];
        if (font) {
            // It's actually a font name, not a font family name,
            // but we'll do what was meant, not what was said.
            familyName = font.familyName;
            fontWeight = weight ? fontWeight : JVSWeightOfFont(font);
            isItalic = style ? isItalic : JVSFontIsItalic(font);
            isCondensed = JVSFontIsCondensed(font);
        } else {
            // Not a valid font or family
            //            JVSLogError(@"Unrecognized font family '%@'", familyName);
            if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
                font = [UIFont systemFontOfSize:fontSize weight:fontWeight];
            } else if (fontWeight > UIFontWeightRegular) {
                font = [UIFont boldSystemFontOfSize:fontSize];
            } else {
                font = [UIFont systemFontOfSize:fontSize];
            }
        }
    }
    
    // Get the closest font that matches the given weight for the fontFamily
    UIFont *bestMatch = font;
    CGFloat closestWeight = INFINITY;
    for (NSString *name in [UIFont fontNamesForFamilyName:familyName]) {
        UIFont *match = [UIFont fontWithName:name size:fontSize];
        if (isItalic == JVSFontIsItalic(match) &&
            isCondensed == JVSFontIsCondensed(match)) {
            CGFloat testWeight = JVSWeightOfFont(match);
            if (ABS(testWeight - fontWeight) < ABS(closestWeight - fontWeight)) {
                bestMatch = match;
                closestWeight = testWeight;
            }
        }
    }
    
    return bestMatch;
}


+ (id)jsonFromNSError:(NSError *)error{
    return error ? [self jsonFromNSErrorDomain:error.domain code:error.code message:error.localizedDescription] : [NSNull null];
}

+ (id)jsonFromNSErrorDomain:(NSString *)domain code:(NSInteger)code message:(NSString *)message{
    return @{
             @"message": message ? message : [NSNull null],
             @"code": @(code),
             @"domain": domain ? domain : [NSNull null],
             };
}
@end
