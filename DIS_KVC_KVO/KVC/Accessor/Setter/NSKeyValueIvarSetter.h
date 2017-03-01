//
//  NSKeyValueIvarSetter.h
//  KVOIMP
//
//  Created by JK on 2017/1/7.
//  Copyright © 2017年 JK. All rights reserved.
//

#import "NSKeyValueSetter.h"

@interface NSKeyValueIvarSetter : NSKeyValueSetter

- (struct objc_ivar *)ivar;
- (id)initWithContainerClassID:(id)containerClassID key:(NSString *)key containerIsa:(Class)containerIsa ivar:(Ivar)ivar;

@end