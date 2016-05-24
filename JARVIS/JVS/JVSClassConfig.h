//
//  JVSClassConfig.h
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol JVSExport;
@class JVSBridge;

@interface JVSClassConfig : NSObject

@property (nonatomic, assign, readonly) long long tag;
@property (nonatomic, assign, readonly) Class moduleClass;
@property (nonatomic, strong, readonly) NSArray<NSArray *> *properties; //[[key, value]]
@property (nonatomic, assign, readonly) BOOL loaded;

-(NSDictionary *)propertyList;

-(id <JVSExport>)     getInstance;

-(void)     mapInstance:(id <JVSExport>)instance;

-(id)initWithBridge:(JVSBridge *)bridge moduleClass:(Class)moduleClass setting:(NSDictionary *)setting;

+(id)ClassConfigWithBridge:(JVSBridge *)bridge setting:(NSDictionary *)setting;

@end
