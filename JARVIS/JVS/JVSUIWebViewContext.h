//
//  JVSUIWebViewContext.h
//  JARVIS
//
//  Created by Hao on 16/5/19.
//  Copyright © 2016年 RainbowColors. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JVSContext.h"

@interface JVSUIWebViewContext : NSObject<JVSContext>

@property (nonatomic, strong) NSString *baseURL;
- (void)refresh;

@property (nonatomic, strong) void (^refreshBlock)(void);

@end
