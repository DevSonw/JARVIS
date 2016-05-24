//
//  JVSClassConfig.m
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import "JVSClassConfig.h"
#import "JVSBridge.h"

@implementation JVSClassConfig{
    NSString *_moduleName;
    JVSBridge *_bridge;
}

@synthesize tag = _tag, moduleClass = _moduleClass, properties = _properties, loaded = _loaded;

+(id)ClassConfigWithBridge:(JVSBridge *)bridge setting:(NSDictionary *)setting{
    
    Class moduleClass = [JVSBridge classForModuleName:setting[@"moduleName"]];
    
    if (moduleClass && [setting isKindOfClass:[NSDictionary class]] && setting[@"tag"]) {
        return [[self alloc] initWithBridge:bridge moduleClass:moduleClass setting:setting];
    }
    return nil;
}


-(id)initWithBridge:(JVSBridge *)bridge moduleClass:(__unsafe_unretained Class)moduleClass setting:(NSDictionary *)setting{
    if (self = [super init]) {
        _moduleName = setting[@"moduleName"];
        _bridge = bridge;
        _moduleClass = moduleClass;
        _tag = [setting[@"tag"] longLongValue];
        _loaded = [setting[@"loaded"] boolValue];
        if ([self getInstance]) {
            _loaded = YES;
        }
        _properties = setting[@"properties"];
    }
    return self;
}

-(id <JVSExport>)     getInstance{
    return [_bridge getInstance:_tag];
}

-(void)     mapInstance:(id <JVSExport>)instance{
    [_bridge mapInstance:instance tag:_tag properties:_properties];
}

-(NSDictionary *)propertyList{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSArray *ar in self.properties) {
        dict[ar[0]] = ar[1];
    }
    return dict;
}

@end
