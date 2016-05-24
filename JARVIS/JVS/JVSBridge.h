//
//  JVSBridge.h
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JVSContext.h"


@protocol JVSExport;

@interface JVSBridge : NSObject

@property (nonatomic, strong, readonly) id<JVSContext> context;

-(id)      initWithContext:(id <JVSContext>)context;

-(void)    mapInstance:(id <JVSExport>)instance moduleName:(NSString *)moduleName;

-(void)    triggerEvent:(id <JVSExport>)instance name:(NSString *)name data:(id)data;

-(id<JVSExport>) getInstance:(long long)tag;
-(long long) tagForInstance:(id<JVSExport>) instance;

-(void)    mapInstance:(id <JVSExport>)instance tag:(long long)tag properties:(NSArray *)properties;

+ (nullable Class)classForModuleName:(nullable NSString *)name;

+  (NSDictionary *)modules;

@end
