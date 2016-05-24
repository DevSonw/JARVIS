//
//  JVSJavaScriptCoreContext.m
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import "JVSJavaScriptCoreContext.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/message.h>
#import <pthread.h>

@interface JVSJavaScriptCoreContext()

@property (nonatomic, strong, readonly) JSContext *context;
@property(nonatomic, retain) NSMutableDictionary<NSNumber *, NSTimer *> *timers;
@property(nonatomic, assign) long timerCount;
@end

@implementation JVSJavaScriptCoreContext{
    NSMutableArray *_scripts;
    NSMutableArray *_sourceURLs;
    NSThread *_javaScriptThread;
}

@synthesize receiver = _receiver;

+ (void)runRunLoopThread
{
    @autoreleasepool {
        // copy thread name to pthread name
        pthread_setname_np([NSThread currentThread].name.UTF8String);
        
        // Set up a dummy runloop source to avoid spinning
        CFRunLoopSourceContext noSpinCtx = {0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL};
        CFRunLoopSourceRef noSpinSource = CFRunLoopSourceCreate(NULL, 0, &noSpinCtx);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), noSpinSource, kCFRunLoopDefaultMode);
        CFRelease(noSpinSource);
        // run the run loop
        while (kCFRunLoopRunStopped != CFRunLoopRunInMode(kCFRunLoopDefaultMode, ((NSDate *)[NSDate distantFuture]).timeIntervalSinceReferenceDate, NO)) {
            NSAssert(NO, @"not reached assertion"); // runloop spun. that's bad.
        }
    }
}

- (void)dealloc
{
    CFRunLoopStop([[NSRunLoop currentRunLoop] getCFRunLoop]);
}

- (void)executeBlockOnJavaScriptQueue:(dispatch_block_t)block
{
    if ([NSThread currentThread] != _javaScriptThread) {
        [self performSelector:@selector(executeBlockOnJavaScriptQueue:)
                     onThread:_javaScriptThread withObject:block waitUntilDone:NO];
    } else {
        block();
    }
}

- (id)init{
    if (self = [super init]) {
        _context = [JSContext new];
        _scripts = [NSMutableArray new];
        _sourceURLs = [NSMutableArray new];
        
        self.timerCount = 0;
        self.timers = [NSMutableDictionary dictionary];
        
        NSThread *javaScriptThread = [[NSThread alloc] initWithTarget:[self class]
                                                             selector:@selector(runRunLoopThread)
                                                               object:nil];
        javaScriptThread.name = @"com.jarvis.javascript";
        
        if ([javaScriptThread respondsToSelector:@selector(setQualityOfService:)]) {
            [javaScriptThread setQualityOfService:NSOperationQualityOfServiceUserInteractive];
        } else {
            javaScriptThread.threadPriority = [NSThread mainThread].threadPriority;
        }
        
        [javaScriptThread start];
        _javaScriptThread = javaScriptThread;
        
        __weak JVSJavaScriptCoreContext *weakSelf = self;
        _context[@"__JVSContextSend"] =  ^(NSString *method, NSString *args) {
            //            NSLog(@"__JVSContextSend: %@, %@", method, args);
            [weakSelf performSelectorOnMainThread:@selector(callReceiver:) withObject:@[method, args ? args : @""] waitUntilDone:NO];
        };
        
        //TODO: test release
        self.context[@"setTimeout"] = ^(JSValue* function, JSValue* timeout) {
            if (weakSelf) {
                weakSelf.timerCount++;
                weakSelf.timers[@(weakSelf.timerCount)] = [NSTimer scheduledTimerWithTimeInterval:(int64_t)([timeout toInt32] / 1000) target:weakSelf selector:@selector(runTimeout:) userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@(weakSelf.timerCount), @"id", function, @"fun", nil] repeats:NO];
                return weakSelf.timerCount;
            }
            return (long)0;
        };
        
        self.context[@"clearTimeout"] = ^(JSValue* num) {
            if (weakSelf && num && [num toInt32]) {
                NSNumber *key = @([num toInt32]);
                if (weakSelf.timers[key]) {
                    [weakSelf.timers[key] invalidate];
                    [weakSelf.timers removeObjectForKey:key];
                    return 1;
                }
            }
            return 0;
        };
        
    }
    
    return self;
}

- (void)invalidate{
    for (NSNumber *key in self.timers) {
        [self.timers[key] invalidate];
        [self.timers removeObjectForKey:key];
    }
}

-(void)runTimeout:(NSTimer *)inTimer{
    [self executeBlockOnJavaScriptQueue:^{
        [self runTimeoutSafe:inTimer];
    }];
}

-(void)runTimeoutSafe:(NSTimer *)inTimer{
    if (inTimer.userInfo[@"fun"]) {
        [inTimer.userInfo[@"fun"] callWithArguments:@[]];
    }
    if (inTimer.userInfo[@"id"]) {
        [self.timers removeObjectForKey:inTimer.userInfo[@"id"]];
    }
    [inTimer invalidate];
}

- (void)callReceiver:(NSArray *)args{
    if (self.receiver) {
        self.receiver(args[0], JVSJSONParse(args[1], NO, NULL));
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
    }
}

- (void)run:(JVSContextCompleteBlock)onComplete{
    [self executeBlockOnJavaScriptQueue:^{
        NSUInteger len = [_scripts count];
        NSError *err;
        for (int i = 0; i < len; i++) {
            err = [self _execScript:_scripts[i] sourceURL:_sourceURLs[i]];
            if (err) {
                break;
            }
        }
        if (onComplete) {
            onComplete(err);
        }
    }];
}

- (NSError *)_execScript:(NSData *)script
               sourceURL:(NSString *)sourceURL{
    JSGlobalContextRef ctx = _context.JSGlobalContextRef;
    NSMutableData *nullTerminatedScript = [NSMutableData dataWithCapacity:script.length + 1];
    
    [nullTerminatedScript appendData:script];
    [nullTerminatedScript appendBytes:"" length:1];
    JSValueRef exceptionValue = NULL;
    JSStringRef scriptJS = JSStringCreateWithUTF8CString(nullTerminatedScript.bytes);
    JSStringRef sourceURLJS = sourceURL ? JSStringCreateWithCFString((__bridge CFStringRef)sourceURL) : NULL;
    JSEvaluateScript(ctx, scriptJS, NULL, sourceURLJS, 0, &exceptionValue);
    if (sourceURLJS)
        JSStringRelease(sourceURLJS);
    JSStringRelease(scriptJS);
    
    
    if (exceptionValue){
        JSGlobalContextRef contextJSRef = JSContextGetGlobalContext(ctx);
        JSObjectRef globalObjectJSRef = JSContextGetGlobalObject(ctx);
        JSValueRef errorJSRef = NULL;
        JSStringRef methodJSStringRef = JSStringCreateWithUTF8CString("uncaughtException");
        JSValueRef methodRef = JSObjectGetProperty(contextJSRef, globalObjectJSRef, methodJSStringRef, &errorJSRef);
        JSStringRelease(methodJSStringRef);
        if (methodRef != NULL && errorJSRef == NULL && JSValueIsObject(contextJSRef, methodRef)) {
            JSValueRef args[1];
            args[0] = exceptionValue;
            __unused JSValueRef resultJSRef = JSObjectCallAsFunction(contextJSRef, (JSObjectRef)methodRef, globalObjectJSRef, 1, args, &errorJSRef);
        }
        return JVSNSErrorFromJSError(_context.JSGlobalContextRef, exceptionValue);
    }
    return nil;
}


- (void)execScript:(NSData *)script
         sourceURL:(NSString *)sourceURL onComplete:(JVSContextCompleteBlock)onComplete{
    [self executeBlockOnJavaScriptQueue:^{
        NSError *err = [self _execScript:script sourceURL:sourceURL];
        if (onComplete) {
            onComplete(err);
        }
    }];
}

- (void)callMethod:(NSString *)method
         arguments:(NSArray *)args{
    //    NSLog(@"callMethod %@, %@", method, args);
    NSString *script = [NSString stringWithFormat:@"__JVSConextReceiver('%@', %@)", method, JVSJSONStringify(args, nil)];
    [self execScript:[script dataUsingEncoding:NSUTF8StringEncoding] sourceURL:nil onComplete:^(NSError *error) {
        if (error) {
#if JVS_DEBUG
            NSLog(@"JSError: %@", error);
#endif
        }
    }];
}

@end
