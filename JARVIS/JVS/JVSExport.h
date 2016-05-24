//
//  JVSExport.h
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JVSClassConfig.h"
#import "JVSBridge.h"
#import "JVSConvert.h"

#define _JVS_CONCAT2(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, ...) A1##_0_##A2##_0_##A3##_0_##A4##_0_##A5##_0_##A6##_0_##A7##_0_##A8##_0_##A9
#define _JVS_CONCAT(...) _JVS_CONCAT2(__VA_ARGS__, _, _, _, _, _, _, _, _, _, _)

#define JVSExport(Selector, ...) @optional Selector _JVS_CONCAT(__JVS_EXPORT__, __VA_ARGS__):(id)argument; @required Selector
//#define JVSConvertOne(Selector, ...) @optional _JVS_CONCAT(Selector, __JVS_EXPORT__, __VA_ARGS__); @required Selector

@class JVSBridge;

typedef void (^JVSCallback)(NSError *error, NSArray *args);

@protocol JVSExport

@optional

/**
 The method for custom module name.
 @return The module name.
 */
+ (NSString *)moduleName;

/**
 The method for custom instance create.
 @param properties Instance properties.
 */
+ (id)instanceWithConfig:(JVSClassConfig *)classConfig;


@property (nonatomic, weak, readonly) JVSBridge *bridge; ///< The bridge for trigger events.

@end


@interface JVSModule : NSObject<JVSExport>
@end
