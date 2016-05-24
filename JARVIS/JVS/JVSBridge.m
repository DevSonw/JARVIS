//
//  JVSBridge.m
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import "JVSBridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "JVSConvert.h"
#import "JVSClassConfig.h"
#import "JVSExport.h"

NSString *JVSEncodeType(const char *type){
    switch (type[0]) {
        case _C_ID:{
            size_t len = strlen(type);
            if (len > 3) {
                char name[len - 2];
                name[len - 3] = '\0';
                memcpy(name, type + 2, len - 3);
                return [NSString stringWithUTF8String:name];
            }
        };
        case _C_STRUCT_B:
        default:
            return [NSString stringWithUTF8String:type];
    }
    return @"";
}

@interface JVSModuleMethod : NSObject

@property (nonatomic, strong) NSString *moduleName;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) id cls;
@property (nonatomic, assign) SEL method;
@property (nonatomic, assign) SEL setter;

@property (nonatomic, strong) NSString *returnType;
@property (nonatomic, strong) NSArray *argumentTypes;

@end

@implementation JVSModuleMethod

@synthesize moduleName, name = _name, cls, method, returnType, argumentTypes, setter;

-(id)initWithMethod:(struct objc_method_description)method_desc{
    if (self = [super init]) {
        self.method = method_desc.name;
        NSString *str = [NSString stringWithUTF8String:sel_getName(self.method)];
        NSArray *args = [str componentsSeparatedByString:@":"];
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes: method_desc.types];
        
        self.returnType = JVSEncodeType([sig methodReturnType]);
        NSUInteger len = [sig numberOfArguments];
        NSMutableArray *ar = [NSMutableArray arrayWithCapacity:len];
        for (int i = 2; i < len; i++) {
            [ar addObject:JVSEncodeType([sig getArgumentTypeAtIndex:i])];
        }
        self.argumentTypes = ar;
        self.name =[args objectAtIndex:0];
    }
    return self;
}



-(id)initWithProperty:(objc_property_t)property{
    if (self = [super init]) {
        self.name = [NSString stringWithUTF8String:property_getName(property)];
        self.method = NSSelectorFromString(_name);//Getter
        
        self.setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:", [_name substringToIndex:1].uppercaseString, [_name substringFromIndex:1]]);
        
        unsigned int attrCount;
        //https://github.com/ibireme/YYModel/blob/master/YYModel/YYClassInfo.m
        objc_property_attribute_t *attrs = property_copyAttributeList(property, &attrCount);
        for (unsigned int i = 0; i < attrCount; i++) {
            switch (attrs[i].name[0]) {
                case 'T':{
                    self.returnType = JVSEncodeType(attrs[i].value);
                    self.argumentTypes = [NSArray arrayWithObject:self.returnType];
                } break;
                case 'G':{
                    self.method = NSSelectorFromString([NSString stringWithUTF8String:attrs[i].value]);
                    
                } break;
                case 'S':{
                    self.setter = NSSelectorFromString([NSString stringWithUTF8String:attrs[i].value]);
                } break;
                    
                default: break;
            }
        }
    }
    return self;
}

-(void)mapArgumentTypes:(NSArray *)ar{
    NSUInteger len = [self.argumentTypes count];
    if ([ar count] > len) {
        NSString *sep = @"_";
        NSMutableArray *types = [NSMutableArray arrayWithArray:self.argumentTypes];
        for (int i = 0; i < len; i++) {
            if (![ar[i] isEqualToString:sep]) {
                [types replaceObjectAtIndex:i withObject:ar[i]];
            }
        }
        self.argumentTypes = types;
        //        if (![ar[0] isEqualToString:sep]) {
        //            self.returnType = ar[0];
        //        }
    }
}

- (NSString *)description{
    return [NSString stringWithFormat:@"<%@: %p> name=%@, method=%@, arguments=%@, return=%@", NSStringFromClass(self.class), &self, self.name, NSStringFromSelector(self.method), [self.argumentTypes componentsJoinedByString:@","], self.returnType];
}

@end


static NSMutableDictionary<NSString *, NSDictionary *> *JVSModules;
static NSMutableDictionary<NSString *, Class> *JVSModuleClasses;
static NSMapTable<Class, NSString *> *JVSModuleKeyClasses;

static NSMutableDictionary<NSString *, JVSModuleMethod *> *JVSModuleInstanceMethods;
static NSMutableDictionary<NSString *, JVSModuleMethod *> *JVSModuleClassMethods;
static NSMutableDictionary<NSString *, JVSModuleMethod *> *JVSModulePropertyMethods;


NSString *JVSModuleNameForClass(Class cls)
{
    NSString *name = nil;
    
    if ([cls respondsToSelector:@selector(moduleName)]) {
        name = [cls moduleName];
    }else{
        name = NSStringFromClass(cls);
        
    }
    if (name.length == 0) {
        name = NSStringFromClass(cls);
    }
    if ([name hasPrefix:@"JVS"]) {
        name = [name stringByReplacingCharactersInRange:(NSRange){0,@"JVS".length} withString:@""];
    }
    return name;
}

NSString *JVSKeyForMethod(NSString *moduleName, NSString *name){
    return [NSString stringWithFormat:@"%@-%@", moduleName, name];
}

NSDictionary *JVSModuleMethodArgumentsMapper(struct objc_method_description *methods, unsigned int count){
    NSMutableDictionary *mapper = [NSMutableDictionary dictionary];
    for( unsigned int k = 0; k < count; ++k ) {
        NSString *str = [NSString stringWithUTF8String:sel_getName(methods[k].name)];
        NSArray *ar = [str componentsSeparatedByString:@"__JVS_EXPORT__"];
        if ([ar count] == 2) {
            NSString *name = ar[0];
            NSArray *args = [[ar[1] substringFromIndex:3] componentsSeparatedByString:@"_0_"];
            [mapper setObject:args forKey:name];
        }
    }
    return mapper;
}

void JVSRegisterModule(Class cls)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        JVSModules = [NSMutableDictionary new];
        JVSModuleInstanceMethods = [NSMutableDictionary new];
        JVSModuleClassMethods = [NSMutableDictionary new];
        JVSModulePropertyMethods = [NSMutableDictionary new];
        JVSModuleClasses = [NSMutableDictionary new];
        JVSModuleKeyClasses = [NSMapTable mapTableWithKeyOptions:NSMapTableWeakMemory valueOptions:NSMapTableCopyIn];
        
        
    });
    
    // Register module
    NSString *moduleName = JVSModuleNameForClass(cls);
    if (!moduleName) {
        //TODO: check
        return;
    }
    if([JVSModules objectForKey:moduleName]){
        //TODO: check repeat.
        return;
    }
    
    [JVSModuleClasses setObject:cls forKey:moduleName];
    [JVSModuleKeyClasses setObject:moduleName forKey:cls];
    
    Class _cls = cls;
    Protocol *protocol = @protocol(JVSExport);
    NSMutableArray *_properties = [NSMutableArray array];
    NSMutableDictionary *_propertyMethods = [NSMutableDictionary dictionary];
    
    NSMutableArray *_instanceMethods = [NSMutableArray array];
    NSMutableArray *_classMethods = [NSMutableArray array];
    
    for( ; cls; cls = [cls superclass] )
    {
        unsigned int protocolCount = 0;
        Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cls, &protocolCount);
        for( unsigned int i = 0; i < protocolCount; ++i )
        {
            if( protocol_conformsToProtocol(protocols[i], protocol) )
            {
                unsigned int count = 0;
                struct objc_method_description *methods = protocol_copyMethodDescriptionList(protocols[i], NO, YES, &count);
                NSDictionary *instanceArgs = JVSModuleMethodArgumentsMapper(methods, count);
                free(methods);
                methods = NULL;
                unsigned int count1 = 0;
                struct objc_method_description *methods1 = protocol_copyMethodDescriptionList(protocols[i], NO, NO, &count1);
                NSDictionary *classArgs = JVSModuleMethodArgumentsMapper(methods1, count1);
                free(methods1);
                methods1 = NULL;
                
                unsigned int propertyCount = 0;
                objc_property_t *properties = protocol_copyPropertyList(protocols[i], &propertyCount);
                
                unsigned int instanceMethodCount = 0;
                struct objc_method_description *instanceMethods = protocol_copyMethodDescriptionList(protocols[i], YES, YES, &instanceMethodCount);
                //
                unsigned int classMethodCount = 0;
                struct objc_method_description *classMethods = protocol_copyMethodDescriptionList(protocols[i], YES, NO, &classMethodCount);
                
                for( unsigned int j = 0; j < propertyCount; ++j ) {
                    JVSModuleMethod *method = [[JVSModuleMethod alloc] initWithProperty:properties[j]];
                    method.cls = _cls;
                    method.moduleName = moduleName;
                    [_properties addObject:method.name];
                    NSString *name = NSStringFromSelector(method.setter);
                    [_propertyMethods setObject:@(1) forKey:NSStringFromSelector(method.method)];
                    [_propertyMethods setObject:@(1) forKey:name];
                    [JVSModulePropertyMethods setObject:method forKey:JVSKeyForMethod(moduleName, method.name)];
                    if ([instanceArgs objectForKey:name]) {
                        //Custom property type
                        [method mapArgumentTypes:instanceArgs[name]];
                    }
                }
                
                for( unsigned int k = 0; k < instanceMethodCount; ++k ) {
                    JVSModuleMethod *method = [[JVSModuleMethod alloc] initWithMethod:instanceMethods[k]];
                    if(! _propertyMethods[NSStringFromSelector(method.method)]){
                        method.cls = _cls;
                        method.moduleName = moduleName;
                        [_instanceMethods addObject:method.name];
                        [JVSModuleInstanceMethods setObject:method forKey:JVSKeyForMethod(moduleName, method.name)];
                        NSString *name = NSStringFromSelector(method.method);
                        if ([instanceArgs objectForKey:name]) {
                            [method mapArgumentTypes:instanceArgs[name]];
                        }
                    }
                }
                
                for( unsigned int m = 0; m < classMethodCount; ++m ) {
                    JVSModuleMethod *method = [[JVSModuleMethod alloc] initWithMethod:classMethods[m]];
                    method.cls = _cls;
                    method.moduleName = moduleName;
                    [_classMethods addObject:method.name];
                    [JVSModuleClassMethods setObject:method forKey:JVSKeyForMethod(moduleName, method.name)];
                    NSString *name = NSStringFromSelector(method.method);
                    if ([classArgs objectForKey:name]) {
                        [method mapArgumentTypes:classArgs[name]];
                    }
                }
                
                free(properties);
                properties = NULL;
                free(instanceMethods);
                instanceMethods = NULL;
                free(classMethods);
                classMethods = NULL;
            }
        }
        free(protocols);
        protocols = NULL;
    }
    
    [JVSModules setObject:@{
                            @"moduleName"      : moduleName,
                            @"properties"      : _properties,
                            @"instanceMethods" : _instanceMethods,
                            @"classMethods"    : _classMethods
                            } forKey:moduleName];
    
}

@class JVSModuleMirror;
@interface JVSBridge()

@property (nonatomic, strong, readonly) NSMapTable<NSNumber *, JVSModuleMirror *> *instances;
- (void)triggerEventWithTag:(long long)tag name:(NSString *)name data:(id)data;

@end

@interface JVSModuleMirror : NSObject

@property (nonatomic, assign, readonly) long long tag;
@property (nonatomic, weak, readonly) id<JVSExport> instance;
@property (nonatomic, weak, readonly) JVSBridge *bridge;
@property (nonatomic, strong) NSString *moduleName;

-(id)initWithTag:(long long)tag instance:(id<JVSExport>) instance bridge:(JVSBridge *)bridge moduleName:(NSString *)moduleName;

@end

static long long JVSModuleInstanceTag = -1;
static char JVSModuleMirrorKey;

@implementation JVSModuleMirror{
}

@synthesize bridge = _bridge, instance = _instance, moduleName = _moduleName;

+(instancetype)moduleMirrorFromInstance:(id<JVSExport>)instance{
    return objc_getAssociatedObject(instance, &JVSModuleMirrorKey);
}

-(id)initWithTag:(long long)tag instance:(id<JVSExport>)instance bridge:(JVSBridge *)bridge moduleName:(NSString *)moduleName{
    if (self = [super init]) {
        _bridge = bridge;
        self.moduleName = moduleName;
        if (tag == 0) {
            tag = JVSModuleInstanceTag --;
        }
        _tag = tag;
        _instance = instance;
        
        if ([(id)instance respondsToSelector:@selector(bridge)]) {
            @try {
                [(id)instance setValue:bridge forKey:@"bridge"];
            }
            @catch (NSException *exception) {
            }
        }
        
        objc_setAssociatedObject(instance, &JVSModuleMirrorKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        [self.bridge.instances setObject:self forKey:@(self.tag)];
        if (tag > 0) {
            [self.bridge triggerEventWithTag:self.tag name:@"load" data:nil];
        }
    }
    return self;
}

- (void)dealloc{
    [self.bridge triggerEventWithTag:self.tag name:@"unload" data:nil];
    [self.bridge.instances removeObjectForKey:@(self.tag)];
    
#if JVS_DEBUG
    NSLog(@"dealloc module %@", @(self.tag));
#endif
    
}

@end

static char JVSCallbackMirrorKey;

@interface JVSCallbackMirror : NSObject

@property (nonatomic, weak, readonly) id<JVSContext> context;
@property (nonatomic, copy, readonly) id callbackId;
@property (nonatomic, assign) long callCount;

-(id)initWithContext:(id<JVSContext>)context callbackId:(NSNumber *)callbackId;

@end

@implementation JVSCallbackMirror{
}

-(id)initWithContext:(id<JVSContext>)context callbackId:(NSNumber *)callbackId{
    _context = context;
    _callbackId = callbackId;
    self.callCount = 0;
    return self;
}

-(void)dealloc{
#if JVS_DEBUG
    NSLog(@"cleanCallback: %@", self.callbackId);
#endif
    if (self.callbackId) {
        [self.context callMethod:@"cleanCallback" arguments:@[self.callbackId]];
    }
}

@end

@implementation JVSBridge

@synthesize instances = _instances;

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if JVS_DEBUG
        NSDate *start = [NSDate new];
#endif
        static unsigned int classCount;
        Class *classes = objc_copyClassList(&classCount);
        Protocol *protocol = @protocol(JVSExport);
        for (unsigned int i = 0; i < classCount; i++)
        {
            Class cls = classes[i];
            if (class_conformsToProtocol(cls, protocol)){
                JVSRegisterModule(cls);
            }
        }
        free(classes);
#if JVS_DEBUG
        NSLog(@"Register modules cost: %fms", [[NSDate new] timeIntervalSinceDate:start]);
        NSLog(@"JVSModules %@\n JVSModuleClassMethods:%@\nJVSModuleInstanceMethods:%@\nJVSModulePropertyMethods:%@", JVSModules, JVSModuleClassMethods, JVSModuleInstanceMethods, JVSModulePropertyMethods);
#endif
    });
}

-(id)  initWithContext:(id <JVSContext>)context{
    if (self = [super init]) {
        _context = context;
        __weak JVSBridge *weakSelf = self;
        _instances = [NSMapTable mapTableWithKeyOptions:NSMapTableCopyIn valueOptions:NSMapTableWeakMemory];
        [_context setReceiver:^(NSString *method, NSArray *args){
            if ([method isEqualToString:@"callClassMethod"]) {
                [weakSelf callClass:args[0] method:args[1] args:args[2] callbackIds:args.count > 3 ? args[3] : nil];
            } else if ([method isEqualToString:@"callInstanceMethod"]) {
                [weakSelf callInstance:args[0] method:args[1] args:args[2] callbackIds:args.count > 3 ? args[3] : nil];
            } else if ([method isEqualToString:@"callProperty"]) {
                [weakSelf callProperty:args[0] method:args[1] args:args[2] isSet:[args[3] boolValue] callbackIds:args.count > 4 ? args[4] : nil];
            }
        }];
    }
    return self;
}

- (void)invokeMethod:(NSInvocation *)anInvocation args:(NSArray *)args moduleMethod:(JVSModuleMethod *)moduleMethod{
    NSMethodSignature *sig = anInvocation.methodSignature;
    NSUInteger length = sig.numberOfArguments - 2;
    NSUInteger argsLen = [args count];
    if (length) {
        for (int i = 0; i < length; i++) {
            NSString *type = [moduleMethod.argumentTypes objectAtIndex:i];
            const char *objcType = [sig getArgumentTypeAtIndex:i + 2];
            id json = argsLen > i ? [args objectAtIndex:i] : [NSNull null];
            
            SEL sel = nil;
            BOOL twoArgs = NO;
            
            SEL selWithBridge = NSSelectorFromString([NSString stringWithFormat:@"%@:bridge:", type]);
            SEL selWithoutBridge = NSSelectorFromString([NSString stringWithFormat:@"%@:", type]);
            
            if ([JVSConvert respondsToSelector:selWithBridge]) {
                sel = selWithBridge;
                twoArgs = YES;
            }  else if ([JVSConvert respondsToSelector:selWithoutBridge]) {
                sel = selWithoutBridge;
            }
            
            switch (objcType[0]) {
                case _C_ID:{
                    id value = nil;
                    
                    static const char *blockType = @encode(typeof(^{}));
                    
                    if (!sel) {
                        //JVSModule
                        Class cls = NSClassFromString(type);
                        if (cls && [JVSModuleKeyClasses objectForKey:cls]) {
                            sel = @selector(JVSModule:bridge:);
                            twoArgs = YES;
                        }
                    }
                    if (sel) {
                        if (twoArgs) {
                            //Convert type with bridge.
                            id (*convert)(id, SEL, id, id) = (typeof(convert))objc_msgSend;
                            value = convert([JVSConvert class], sel, json, self);
                        } else {
                            //Convert type.
                            id (*convert)(id, SEL, id) = (typeof(convert))objc_msgSend;
                            value = convert([JVSConvert class], sel, json);
                        }
                    } else if (!strcmp(objcType, blockType)) {
                        //Block
                        __weak JVSBridge *weakSelf = self;
                        if (json && json != [NSNull null]) {
                            JVSCallbackMirror *mirror = [[JVSCallbackMirror alloc] initWithContext:self.context callbackId:json];
                            __weak JVSCallbackMirror *weakMirror = mirror;
                            value = ^(NSError *error, NSArray *args) {
                                NSMutableArray *mutArgs = [NSMutableArray arrayWithObject:[JVSConvert jsonFromNSError:error]];
                                //TODO: throw error
                                if (args) {
                                    [mutArgs addObjectsFromArray:args];
                                }
                                weakMirror.callCount ++;
                                [weakSelf callback:json args:mutArgs];
                            };
                            objc_setAssociatedObject(value, &JVSCallbackMirrorKey, mirror, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        } else {
                            //Clean default callback.
                            //                            value = ^(NSError *error, __unused NSArray *_) {
                            //                            };
                        }
                    } else if(json != [NSNull null]){
                        value = json;
                    }
                    if (value) {
                        CFBridgingRetain(value);
                    }
                    [anInvocation setArgument:&value atIndex:i + 2];
                    
                } break;
#define JVS_CASE(_value, _type, getter) \
case _value: { \
_type value;\
if (sel) {\
if (twoArgs) {\
_type (*convert)(id, SEL, id, id) = (typeof(convert))objc_msgSend;\
value = convert([JVSConvert class], sel, json, self);\
} else {\
_type (*convert)(id, SEL, id) = (typeof(convert))objc_msgSend;\
value = convert([JVSConvert class], sel, json);\
}\
} else {\
value = [[JVSConvert NSNumber:json] getter];\
}\
[anInvocation setArgument:&value atIndex:i + 2];\
} break;
                    JVS_CASE(_C_CHR, char, charValue);
                    JVS_CASE(_C_UCHR, unsigned char, unsignedCharValue);
                    JVS_CASE(_C_SHT, short, shortValue);
                    JVS_CASE(_C_USHT, unsigned short, unsignedShortValue);
                    JVS_CASE(_C_INT, int, intValue);
                    JVS_CASE(_C_UINT, unsigned int, unsignedIntValue);
                    JVS_CASE(_C_LNG, long, longValue);
                    JVS_CASE(_C_ULNG, unsigned long, unsignedLongValue);
                    JVS_CASE(_C_LNG_LNG, long long, longLongValue);
                    JVS_CASE(_C_ULNG_LNG, unsigned long long, unsignedLongLongValue);
                    JVS_CASE(_C_FLT, float, floatValue);
                    JVS_CASE(_C_DBL, double, doubleValue);
                    JVS_CASE(_C_BOOL, BOOL, boolValue);
                case _C_STRUCT_B: {
                    if (sel) {
                        NSMethodSignature *typeSignature = [JVSConvert methodSignatureForSelector:sel];
                        NSInvocation *typeInvocation = [NSInvocation invocationWithMethodSignature:typeSignature];
                        typeInvocation.selector = sel;
                        typeInvocation.target = [JVSConvert class];
                        float *returnValue = malloc(typeSignature.methodReturnLength);
                        [typeInvocation setArgument:&json atIndex:2];
                        __weak JVSBridge *weakSelf = self;
                        if (twoArgs) {
                            [typeInvocation setArgument:&weakSelf atIndex:3];
                        }
                        [typeInvocation invoke];
                        [typeInvocation getReturnValue:returnValue];
                        [anInvocation setArgument:returnValue atIndex:i + 2];
                        free(returnValue);
                    }
                    break;
                }
                default:
                    break;
            }
        }
    }
    
    [anInvocation invoke];
    
    const char* retType = [sig methodReturnType];
    if (argsLen > length && [args[length] isKindOfClass:[NSNumber class]]) {
        //Return callback
        id json = args[length];
        id result;
        if (retType[0] == _C_VOID) {
            result = nil;
        } else if (retType[0] == _C_ID) {
            //http://stackoverflow.com/questions/22018272/nsinvocation-returns-value-but-makes-app-crash-with-exc-bad-access
            void *tmp;
            [anInvocation getReturnValue:&tmp];
            result = (__bridge id)tmp;
        } else {
            //number
            switch (retType[0]) {
#define JVS_RET_CASE(_value, _type, getter) \
case _value: { \
_type val;\
[anInvocation getReturnValue:&val];\
result = [NSNumber getter:val];\
} break;
                    JVS_RET_CASE(_C_CHR, char, numberWithChar);
                    JVS_RET_CASE(_C_UCHR, unsigned char, numberWithUnsignedChar);
                    JVS_RET_CASE(_C_SHT, short, numberWithShort);
                    JVS_RET_CASE(_C_USHT, unsigned short, numberWithUnsignedShort);
                    JVS_RET_CASE(_C_INT, int, numberWithInt);
                    JVS_RET_CASE(_C_UINT, unsigned int, numberWithUnsignedInt);
                    JVS_RET_CASE(_C_LNG, long, numberWithLong);
                    JVS_RET_CASE(_C_ULNG, unsigned long, numberWithUnsignedLong);
                    JVS_RET_CASE(_C_LNG_LNG, long long, numberWithLongLong);
                    JVS_RET_CASE(_C_ULNG_LNG, unsigned long long, numberWithUnsignedLongLong);
                    JVS_RET_CASE(_C_FLT, float, numberWithFloat);
                    JVS_RET_CASE(_C_DBL, double, numberWithDouble);
                    JVS_RET_CASE(_C_BOOL, BOOL, numberWithBool);
                default:
                    break;
            }
        }
        [self callback:json args: [result isKindOfClass:[NSError class]] ? @[[JVSConvert jsonFromNSError:result]] : @[[NSNull null], result ? result : [NSNull null]]];
        [self cleanCallback:json];
    }
    
    for (int i = 0; i < length; i++) {
        if ([sig getArgumentTypeAtIndex:i+2][0] == _C_ID) {
            __unsafe_unretained id value;
            [anInvocation getArgument:&value atIndex:i+2];
            if (value) {
                CFRelease((__bridge CFTypeRef)value);
            }
        }
    }
}

+ (nullable Class)classForModuleName:(nullable NSString *)name{
    return name ? JVSModuleClasses[name] : nil;
}

//TODO: check class
- (void)callClass:(NSString*)moduleName method:(NSString *)method args:(NSArray *)args callbackIds:(NSArray *)callbackIds{
    
    JVSModuleMethod *moduleMethod = [JVSModuleClassMethods objectForKey:JVSKeyForMethod(moduleName, method)];
#if JVS_DEBUG
    NSLog(@"callClassMethod: %@.%@(%@)", moduleName, method, args);
#endif
    if (moduleMethod) {
        SEL selector = moduleMethod.method;
        Class cls = moduleMethod.cls;
        NSInvocation *anInvocation = [NSInvocation
                                      invocationWithMethodSignature:[cls methodSignatureForSelector:selector]];
        [anInvocation setSelector:selector];
        [anInvocation setTarget:[cls class]];
        [self invokeMethod:anInvocation args:args moduleMethod:moduleMethod];
    } else {
        [self cleanCallback:callbackIds];
    }
}

- (void)callInstance:(NSNumber *)tag method:(NSString *)method args:(NSArray *)args callbackIds:(NSArray *)callbackIds{
    JVSModuleMirror *mirror = [self.instances objectForKey:tag];
    id instance = mirror.instance;
#if JVS_DEBUG
    NSLog(@"callInstanceMethod: %@.%@(%@)", instance, method, args);
#endif
    //TODO: check instance
    if (mirror && instance) {
        JVSModuleMethod *moduleMethod = [JVSModuleInstanceMethods objectForKey:JVSKeyForMethod(mirror.moduleName, method)];
        //TODO: throw error when moduleMethod nil.
        if (moduleMethod) {
            Class cls = [instance class];
            SEL selector = moduleMethod.method;
            NSInvocation *anInvocation = [NSInvocation
                                          invocationWithMethodSignature:
                                          [cls instanceMethodSignatureForSelector:selector]];
            [anInvocation setSelector:selector];
            [anInvocation setTarget:instance];
            [self invokeMethod:anInvocation args:args moduleMethod:moduleMethod];
        }
    } else {
        [self cleanCallback:callbackIds];
    }
}

- (void)callProperty:(NSNumber *)tag method:(NSString *)method args:(NSArray *)args isSet:(BOOL)isSet callbackIds:(NSArray *)callbackIds{
    JVSModuleMirror *mirror = [self.instances objectForKey:tag];
    id instance = mirror.instance;
#if JVS_DEBUG
    NSLog(@"callProperty: %@.%@(%@)", instance, method, args);
#endif
    //TODO: check instance
    if (mirror) {
        JVSModuleMethod *moduleMethod = [JVSModulePropertyMethods objectForKey:JVSKeyForMethod(mirror.moduleName, method)];
        if (moduleMethod) {
            [self callProperty:instance moduleMethod:moduleMethod args:args isSet:isSet];
        } else {
            [self cleanCallback:callbackIds];
        }
    } else {
        [self cleanCallback:callbackIds];
    }
}

- (void)callProperty:(id <JVSExport>)instance moduleMethod:(JVSModuleMethod *)moduleMethod args:(NSArray *)args isSet:(BOOL)isSet{
    Class cls = [(id)instance class];
    SEL selector = isSet ? moduleMethod.setter : moduleMethod.method;
    NSInvocation *anInvocation = [NSInvocation
                                  invocationWithMethodSignature:
                                  [cls instanceMethodSignatureForSelector:selector]];
    [anInvocation setSelector:selector];
    [anInvocation setTarget:instance];
    [self invokeMethod:anInvocation args:args moduleMethod:moduleMethod];
}

+  (NSDictionary *)modules{
    return JVSModules;
}

-(id<JVSExport>) getInstance:(long long)tag{
    JVSModuleMirror *mirror = [self.instances objectForKey:@(tag)];
    return mirror.instance;
}

-(long long)tagForInstance:(id<JVSExport>)instance{
    return [JVSModuleMirror moduleMirrorFromInstance:instance].tag;
}

-(void)    mapInstance:(id <JVSExport>)instance tag:(long long)tag properties:(NSArray *)properties{
    if ([JVSModuleMirror moduleMirrorFromInstance:instance]) {
        //TODO: throw error when repeat mapping? check bridge.
        //check instance if JVSExport
    }
    NSString *moduleName = JVSModuleNameForClass([(id)instance class]);
    
    //Set properties.
    for (NSArray *property in properties) {
        JVSModuleMethod *moduleMethod = [JVSModulePropertyMethods objectForKey:JVSKeyForMethod(moduleName, property[0])];
        if (moduleMethod) {
            [self callProperty:instance moduleMethod:moduleMethod args:@[property[1]] isSet:YES];
        }
    }
    
    __unused JVSModuleMirror *mirror = [[JVSModuleMirror alloc] initWithTag:tag instance:instance bridge:self moduleName:moduleName];
    
}

-(void)     mapInstance:(id <JVSExport>)instance moduleName:(NSString *)moduleName{
    if ([JVSModuleMirror moduleMirrorFromInstance:instance]) {
        //TODO: throw error when repeat mapping? check bridge.
        //check instance if JVSExport
    }
    JVSModuleMirror *mirror = [[JVSModuleMirror alloc] initWithTag:0 instance:instance bridge:self moduleName:JVSModuleNameForClass([(id)instance class])];
    [self.context callMethod:@"mapInstance" arguments:@[@(mirror.tag), moduleName]];
}

- (void)triggerEventWithTag:(long long)tag name:(NSString *)name data:(id)data{
#if JVS_DEBUG
    NSLog(@"triggerEvent: %lld, %@, %@", tag, name, data);
#endif
    [self.context callMethod:@"triggerEvent" arguments:@[@(tag), name, data ?: [NSNull null]]];
}

- (void)callback:(NSNumber *)cbId args:(NSArray *)args{
#if JVS_DEBUG
    NSLog(@"callback: %@, %@", cbId, args);
#endif
    [self.context callMethod:@"callback" arguments:@[cbId, args ?: [NSNull null]]];
}

- (void)cleanCallback:(id)cbId{
#if JVS_DEBUG
    NSLog(@"cleanCallback: %@", cbId);
#endif
    if (cbId) {
        [self.context callMethod:@"cleanCallback" arguments:@[cbId]];
    }
}

- (void)triggerEvent:(id <JVSExport>)instance name:(NSString *)name data:(id)data{
    //TODO: Check name and data
    JVSModuleMirror *mirror = [JVSModuleMirror moduleMirrorFromInstance:instance];
    if (mirror) {
        [self triggerEventWithTag:mirror.tag name:name data:data];
    } else {
        //TODO: Error
    }
}

- (void)dealloc{
#if JVS_DEBUG
    NSLog(@"dealloc bridge");
#endif
}

@end